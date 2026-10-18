extends RefCounted

const DEFAULT_RULES = preload("res://content/demo/design_rules_v5.tres")
const RECORD_LIMIT := 65536
var catalog: Resource
var rules: Resource
var _state: Dictionary = {}

func _init(content: Resource = null, definitions: Resource = null) -> void:
	catalog = content
	rules = definitions if definitions != null else DEFAULT_RULES
	reset()

func reset() -> void:
	_state = {"design_version":1, "rules_signature":rules.signature(), "starter_preset_id":"",
		"module_inventory":{}, "module_slots":[], "connections":[], "solute_inventory":{},
		"ground_inventory":{}, "solvent_inventory":{}, "context_inventory":{}, "bottles":[],
		"solute_sources":{}, "ground_sources":{}, "context_sources":{}, "inventory_sources":[], "solvent_reserve":{},
		"context_draft":{}, "context_application":"", "applied_context_sources":[],
		"current_publish_index":0, "skill_applications":[], "skill_application":"",
		"mortar":{"solute_id":"", "count":0}, "chamber_slots":[], "chamber_solvents":{},
		"stirred":false, "lamp_cycles":0, "last_distillation":[], "unlocked_skills":["text"],
		"claimed_events":[], "inventory_log":[], "operations":[]}
	for index in rules.module_slots: _state.module_slots.append("")
	for index in rules.bottle_slots: _state.bottles.append(_empty_bottle(index))
	for entry in rules.solutes:
		_state.solute_inventory[str(entry.id)] = rules.initial_solute_count
		_state.ground_inventory[str(entry.id)] = 0
		_state.solute_sources[str(entry.id)] = []
		_state.ground_sources[str(entry.id)] = []
		for index in rules.initial_solute_count: _state.solute_sources[str(entry.id)].append({"source_instance_id":"initial", "definition_id":"", "preset_id":"", "kind":"solute", "id":str(entry.id), "count":1})
	for entry in rules.solvents:
		_state.solvent_inventory[str(entry.id)] = int(entry.get("initial_count", rules.initial_solvent_count))
		_state.solvent_reserve[str(entry.id)] = 0

func starter_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if catalog == null: return options
	for id in rules.starter_presets:
		var preset: Resource = catalog.find_preset(id)
		if preset == null: continue
		var draft: Dictionary = preset.to_draft({})
		options.append({"id":id, "title":preset.title, "kernel_id":str(preset.kernel_id), "slots":draft.slots,
			"family_anchor":preset.family_anchor, "context_hint":preset.context_hint, "source_presets":[preset.source_record()]})
	return options

func perform(action: String, params: Dictionary = {}) -> PackedStringArray:
	if action in ["claim", "publish", "unlock"]: return PackedStringArray(["该动作只能由模拟账本提交。"])
	return _perform(action, params)

func _perform(action: String, params: Dictionary, source: Dictionary = {}) -> PackedStringArray:
	params = _canonical(params)
	var errors := PackedStringArray()
	if _state.operations.size() >= RECORD_LIMIT: return PackedStringArray(["设计操作记录已达有限上限。"])
	var id := str(params.get("solute_id", ""))
	var slot := -1
	if action in ["fill", "put", "take", "install_module"] or (action == "discard" and params.has("slot")):
		var limit: int = rules.module_slots if action == "install_module" else rules.bottle_slots
		if not _integer(params.get("slot")) or int(params.slot) < 0 or int(params.slot) >= limit:
			return PackedStringArray(["槽位超出有限范围。"])
		slot = int(params.slot)
	match action:
		"choose_starter":
			var preset_id := str(params.get("preset_id", ""))
			if preset_id not in rules.starter_presets or catalog == null or catalog.find_preset(preset_id) == null:
				return PackedStringArray(["开局预设未登记。"])
			if not str(_state.starter_preset_id).is_empty():
				return errors if _state.starter_preset_id == preset_id else PackedStringArray(["本局开局预设已确认。"])
			_state.starter_preset_id = preset_id
			_grant_module(str(catalog.find_preset(preset_id).kernel_id))
		"install_module":
			var module_id := str(params.get("module_id", ""))
			if rules.find("modules", module_id).is_empty() or int(_state.module_inventory.get(module_id, 0)) <= 0:
				return PackedStringArray(["仓库中没有该模块。"])
			var used := 0
			for index in _state.module_slots.size():
				if index != slot and _state.module_slots[index] == module_id: used += 1
			if used >= int(_state.module_inventory[module_id]): return PackedStringArray(["已获得的模块数量不足，不能复制纸片。"])
			_state.module_slots[slot] = module_id
		"connect":
			if not _integer(params.get("from")) or not _integer(params.get("to")):
				return PackedStringArray(["连接槽位类型错误。"])
			var first := int(params.from)
			var second := int(params.to)
			if first < 0 or second < 0 or first >= rules.module_slots or second >= rules.module_slots or first == second or str(_state.module_slots[first]).is_empty() or str(_state.module_slots[second]).is_empty():
				return PackedStringArray(["连接需要两个已放置的不同模块槽。"])
			var connection := {"from":first, "to":second}
			if connection in _state.connections: return PackedStringArray(["该连接已经存在。"])
			_state.connections.append(connection)
		"grind":
			if not _state.solute_inventory.has(id) or int(_state.solute_inventory[id]) <= 0:
				return PackedStringArray(["没有可磨碎的溶质纸块。"])
			if int(_state.mortar.count) != 0: return PackedStringArray(["请先取出或废弃研钵中的粉末。"])
			_state.solute_inventory[id] -= 1
			_state.mortar = {"solute_id":id, "count":1, "source":_state.solute_sources[id].pop_front()}
		"take_ground":
			if int(_state.mortar.count) != 1: return PackedStringArray(["研钵中没有磨好的粉末。"])
			id = str(_state.mortar.solute_id)
			_state.ground_inventory[id] += 1
			_state.ground_sources[id].append(_state.mortar.source)
			_state.mortar = {"solute_id":"", "count":0}
		"fill":
			if _state.bottles[slot].state != "empty": return PackedStringArray(["每瓶只容纳一种溶质，请先取出或废弃。"])
			if not _state.ground_inventory.has(id) or int(_state.ground_inventory[id]) <= 0: return PackedStringArray(["请先磨碎并取出该溶质。"])
			_state.ground_inventory[id] -= 1
			_state.bottles[slot] = {"slot":slot, "state":"filled", "solute_id":id, "solvent_id":"", "context_id":"", "source":_state.ground_sources[id].pop_front()}
		"pour":
			var solvent_id := str(params.get("solvent_id", ""))
			var amount: Variant = params.get("amount", 1)
			if not _integer(amount) or int(amount) < 1 or not _state.solvent_inventory.has(solvent_id) or int(_state.solvent_inventory[solvent_id]) < int(amount):
				return PackedStringArray(["溶剂数量无效或库存不足。"])
			_state.solvent_inventory[solvent_id] -= int(amount)
			_state.chamber_solvents[solvent_id] = int(_state.chamber_solvents.get(solvent_id, 0)) + int(amount)
			var refill := mini(int(_state.solvent_reserve[solvent_id]), int(rules.find("solvents", solvent_id).capacity) - int(_state.solvent_inventory[solvent_id]))
			_state.solvent_inventory[solvent_id] += refill
			_state.solvent_reserve[solvent_id] -= refill
			_state.stirred = false
		"put":
			if _state.bottles[slot].state != "filled": return PackedStringArray(["只有装好粉末的瓶可以投放。"])
			_state.bottles[slot].state = "placed"
			_state.chamber_slots.append(slot)
			_state.stirred = false
		"stir":
			if _state.chamber_slots.is_empty() or _state.chamber_solvents.is_empty(): return PackedStringArray(["先加入溶质与溶剂，再搅拌。"])
			if _state.stirred: return PackedStringArray(["当前溶液已经搅拌。"])
			_state.stirred = true
		"lamp":
			if not _state.stirred or _state.chamber_slots.is_empty() or _state.chamber_solvents.is_empty(): return PackedStringArray(["点灯前需投放并搅拌溶液。"])
			var sequence: Array[Dictionary] = []
			for solvent_id in _state.chamber_solvents:
				sequence.append({"solvent_id":str(solvent_id), "boiling_order":int(rules.find("solvents", str(solvent_id)).boiling_order), "amount":int(_state.chamber_solvents[solvent_id])})
			sequence.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.boiling_order < b.boiling_order or (a.boiling_order == b.boiling_order and a.solvent_id < b.solvent_id))
			var context_parts := PackedStringArray()
			for entry in sequence: context_parts.append(entry.solvent_id)
			for bottle_slot in _state.chamber_slots:
				var bottle: Dictionary = _state.bottles[bottle_slot]
				bottle.state = "solid"
				bottle.context_id = str(bottle.solute_id) + "@" + "+".join(context_parts)
			_state.last_distillation = sequence
			_state.chamber_solvents.clear()
			_state.chamber_slots.clear()
			_state.stirred = false
			_state.lamp_cycles += 1
		"take":
			var bottle: Dictionary = _state.bottles[slot]
			if bottle.state != "solid": return PackedStringArray(["溶剂尚未蒸干，不能取出固体。"])
			_state.context_inventory[str(bottle.context_id)] = int(_state.context_inventory.get(str(bottle.context_id), 0)) + 1
			if not _state.context_sources.has(str(bottle.context_id)): _state.context_sources[str(bottle.context_id)] = []
			_state.context_sources[str(bottle.context_id)].append(bottle.source.duplicate(true))
			_state.bottles[slot] = _empty_bottle(slot)
		"apply_context":
			var context_id := str(params.get("context_id", ""))
			if not params.get("base") is Dictionary: return PackedStringArray(["应用固体需要合法的作者草稿。"])
			var draft := preview_context(context_id, params.base)
			if draft.is_empty(): return PackedStringArray(["没有该固体，或作者草稿字段不合法。"])
			_state.context_inventory[context_id] -= 1
			var provenance: Dictionary = _state.context_sources[context_id].pop_front()
			var sources: Array = draft.get("context_sources", []).duplicate(true)
			sources.append(provenance)
			draft.context_sources = sources
			_state.applied_context_sources.append(provenance.duplicate(true))
			_state.context_draft = draft
			_state.context_application = "%s → 仅修改自己的待发布草稿；原始事件 %s 来源保留。" % [str(rules.find("solutes", context_id.get_slice("@", 0)).title), str(provenance.source_instance_id)]
		"apply_skill":
			var skill_id := str(params.get("skill_id", ""))
			var skill: Dictionary = rules.find("skills", skill_id)
			if skill_id not in _state.unlocked_skills or skill.get("draft_effects", []).is_empty(): return PackedStringArray(["该能力未解锁或没有可应用的草稿作用。"])
			var application := {"publish_index":int(_state.current_publish_index), "skill_id":skill_id}
			if application in _state.skill_applications: return PackedStringArray(["本轮待发布草稿已应用该能力，不能重复堆叠。"])
			if not params.get("base") is Dictionary: return PackedStringArray(["应用能力需要合法的作者草稿。"])
			var draft := _effect_draft(params.base, skill.draft_effects)
			if draft.is_empty(): return PackedStringArray(["作者草稿字段或固体来源不合法。"])
			_state.skill_applications.append(application)
			_state.context_draft = draft
			_state.skill_application = "%s → 仅修改自己的待发布草稿；本轮仅可应用一次。" % str(skill.title)
		"discard":
			if slot >= 0:
				if _state.bottles[slot].state == "empty": return PackedStringArray(["空瓶无可废弃材料。"])
				_state.bottles[slot] = _empty_bottle(slot)
				_state.chamber_slots.erase(slot)
				_state.stirred = false
			else:
				var inventory := str(params.get("source", "ground"))
				if inventory == "mortar":
					if int(_state.mortar.count) == 0: return PackedStringArray(["研钵是空的。"])
					_state.mortar = {"solute_id":"", "count":0}
				elif inventory in ["ground", "solute", "context"]:
					var key: String = {"ground":"ground_inventory", "solute":"solute_inventory", "context":"context_inventory"}[inventory]
					id = str(params.get("context_id", id))
					if int(_state[key].get(id, 0)) <= 0: return PackedStringArray(["没有可废弃的材料。"])
					_state[key][id] -= 1
					_state[{"ground":"ground_sources", "solute":"solute_sources", "context":"context_sources"}[inventory]][id].pop_front()
				else: return PackedStringArray(["废弃来源未登记。"])
		"claim":
			var instance_id := str(params.get("instance_id", ""))
			if instance_id.is_empty() or source.is_empty() or not source.get("acknowledged", false): return PackedStringArray(["只能领取已确认的真实事件纸奖励。"])
			if instance_id in _state.claimed_events: return errors
			var rewards: Variant = source.get("design_rewards", [])
			if not rewards is Array: return PackedStringArray(["事件物资字段类型错误。"])
			for reward: Variant in rewards:
				if not reward is Dictionary or str(reward.get("kind", "")) not in ["module", "solute", "solvent"] or not _integer(reward.get("count")) or int(reward.count) < 1:
					return PackedStringArray(["事件物资记录无效。"])
				var kind: String = {"module":"modules", "solute":"solutes", "solvent":"solvents"}[str(reward.kind)]
				if rules.find(kind, str(reward.get("id", ""))).is_empty(): return PackedStringArray(["事件物资未登记。"])
			var labels := PackedStringArray()
			for reward: Dictionary in rewards:
				var count := int(reward.count)
				var reward_id := str(reward.id)
				var kind := str(reward.kind)
				var provenance := {"source_instance_id":instance_id, "definition_id":str(source.get("definition_id", "")), "preset_id":str(source.get("design_source_preset_id", "")), "kind":kind, "id":reward_id, "count":count}
				_state.inventory_sources.append(provenance.duplicate(true))
				match kind:
					"module":
						for index in count: _grant_module(str(rules.find("modules", reward_id).kernel_id))
					"solute":
						_state.solute_inventory[reward_id] += count
						for index in count:
							var unit := provenance.duplicate(true)
							unit.count = 1
							_state.solute_sources[reward_id].append(unit)
					"solvent":
						var space := int(rules.find("solvents", reward_id).capacity) - int(_state.solvent_inventory[reward_id])
						var filled := mini(count, space)
						_state.solvent_inventory[reward_id] += filled
						_state.solvent_reserve[reward_id] += count - filled
				labels.append("%s ×%d" % [str(rules.find({"module":"modules", "solute":"solutes", "solvent":"solvents"}[kind], reward_id).title), count])
			_state.claimed_events.append(instance_id)
			if not labels.is_empty(): _state.inventory_log.append("事件 %s：%s" % [instance_id, "、".join(labels)])
		"publish":
			if source.is_empty() or not source.get("controlled", false) or not source.get("owned", false) or source.get("creator", "") != "player": return PackedStringArray(["只有玩家已发布版本可登记模块。"])
			_grant_module(str(source.kernel_id))
			_state.current_publish_index += 1
		"unlock":
			var skill_id := str(params.get("skill_id", ""))
			errors = skill_errors(skill_id)
			if not errors.is_empty(): return errors
			_state.unlocked_skills.append(skill_id)
		_:
			return PackedStringArray(["设计动作未登记：" + action])
	_state.operations.append({"action":action, "params":params.duplicate(true)})
	return errors

func _grant_module(kernel_id: String) -> void:
	var id := "module_" + kernel_id
	if rules.find("modules", id).is_empty(): return
	_state.module_inventory[id] = int(_state.module_inventory.get(id, 0)) + 1
	if str(_state.module_slots[0]).is_empty(): _state.module_slots[0] = id

func record_publish(variant: Dictionary) -> PackedStringArray:
	return _perform("publish", {"variant_id":str(variant.get("id", ""))}, variant)

func claim_event(event: Dictionary) -> PackedStringArray:
	return _perform("claim", {"instance_id":str(event.get("instance_id", ""))}, event)

func skill_errors(id: String) -> PackedStringArray:
	var entry: Dictionary = rules.find("skills", id)
	if entry.is_empty(): return PackedStringArray(["传播技能未登记。"])
	if id in _state.unlocked_skills: return PackedStringArray(["该技能已解锁，不能重复扣款。"])
	for dependency in entry.requires:
		if str(dependency) not in _state.unlocked_skills: return PackedStringArray(["请先解锁依赖技能：" + str(dependency)])
	if _state.operations.size() >= RECORD_LIMIT: return PackedStringArray(["设计操作记录已达有限上限。"])
	return PackedStringArray()

func supported_channels() -> Array[String]:
	var ids: Array[String] = []
	for id in _state.unlocked_skills:
		for target in rules.find("skills", str(id)).get("target_ids", []):
			if str(target) not in ids: ids.append(str(target))
	return ids

func preview_context(id: String, base: Dictionary) -> Dictionary:
	if int(_state.context_inventory.get(id, 0)) <= 0: return {}
	var solute: Dictionary = rules.find("solutes", id.get_slice("@", 0))
	if solute.is_empty(): return {}
	return _effect_draft(base, solute.effects)

func _effect_draft(base: Dictionary, effects: Array) -> Dictionary:
	var draft: Dictionary = _canonical(base)
	if not context_sources_valid(draft.get("context_sources", [])): return {}
	for effect: Dictionary in effects:
		var field := str(effect.field)
		if field == "political_position":
			if not draft.get(field) is Array or draft[field].size() != 2: return {}
			var axis := 0 if str(effect.axis) == "x" else 1
			if not _number(draft[field][axis]): return {}
			draft[field][axis] = clampf(float(draft[field][axis]) + float(effect.amount), -1.0, 1.0)
			draft.political_known = true
		else:
			if not _number(draft.get(field)): return {}
			draft[field] = clampf(float(draft[field]) + float(effect.amount), 0.0, 1.0)
	return draft

func context_sources_valid(sources: Variant, applied: Variant = null) -> bool:
	if not sources is Array: return false
	var allowed: Variant = _state.applied_context_sources if applied == null else applied
	if not allowed is Array: return false
	allowed = _canonical(allowed)
	for source: Variant in sources:
		if not source is Dictionary or _canonical(source) not in allowed: return false
	return true

func unlock_skill(id: String) -> PackedStringArray:
	return _perform("unlock", {"skill_id":id})

func snapshot(variants: Array = []) -> Dictionary:
	var result := _state.duplicate(true)
	result.erase("operations")
	result.erase("rules_signature")
	var lineage: Array[Dictionary] = []
	for variant: Dictionary in variants:
		lineage.append({"id":variant.id, "family_id":variant.family_id, "parent_ids":variant.parent_ids.duplicate(),
			"origin_ids":variant.get("origin_ids", []).duplicate(), "source_presets":variant.get("source_presets", []).duplicate(true),
			"kernel_id":variant.kernel_id, "module_id":"module_" + str(variant.kernel_id), "creator":variant.creator,
			"owned":variant.owned, "controlled":variant.controlled, "text":variant.text, "semantic_distance":variant.semantic_distance})
	result.lineage_view = lineage
	result.supported_channels = supported_channels()
	result.explanation = "培养数值与神经拓扑为游戏设计；沸腾顺序不是物理温度。外部版本只读，来源与控制权不变。"
	return result

func payload() -> Dictionary:
	return _state.duplicate(true)

func record_errors() -> PackedStringArray:
	return PackedStringArray(["设计操作记录已达有限上限。"] if _state.operations.size() >= RECORD_LIMIT else [])

func validate_payload(data: Dictionary, events: Array, variants: Array, economy: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	data = _canonical(data)
	if not _integer(data.get("design_version")) or int(data.design_version) != 1 or not data.get("rules_signature") is String or data.rules_signature != rules.signature() or not data.get("operations") is Array or data.operations.size() > RECORD_LIMIT:
		return PackedStringArray(["设计存档版本、定义或操作记录错误。"])
	var replay = get_script().new(catalog, rules)
	var published := {}
	for operation: Variant in data.operations:
		if not operation is Dictionary or not operation.get("action") is String or not operation.get("params") is Dictionary:
			errors.append("设计存档操作类型错误。")
			continue
		var source := {}
		var params: Dictionary = operation.params
		if operation.action == "claim":
			for event: Dictionary in events:
				if str(event.get("instance_id", "")) == str(params.get("instance_id", "")): source = event
		elif operation.action == "publish":
			var id := str(params.get("variant_id", ""))
			if published.has(id): errors.append("设计存档重复发布模块奖励。")
			published[id] = true
			for variant: Dictionary in variants:
				if str(variant.get("id", "")) == id: source = variant
		elif operation.action == "choose_starter" and not published.is_empty(): errors.append("开局选择必须在首发之前。")
		errors.append_array(replay._perform(operation.action, params, source))
	for variant: Dictionary in variants:
		if variant.get("controlled", false) and variant.get("creator", "") == "player" and not published.has(str(variant.get("id", ""))): errors.append("设计存档缺少玩家版本模块来源。")
	if not errors.is_empty(): return errors
	for variant: Dictionary in variants:
		if not replay.context_sources_valid(variant.get("context_sources", [])): errors.append("版本固体来源不符合已应用记录。")
	if _canonical(replay.payload()) != data: errors.append("设计存档状态不符合操作记录，拒绝部分恢复。")
	var purchases := {}
	for transaction: Variant in economy.get("transactions", []):
		if transaction is Dictionary and str(transaction.get("reason", "")).begins_with("技能解锁："):
			var id := str(transaction.reason).trim_prefix("技能解锁：")
			var skill: Dictionary = rules.find("skills", id)
			if skill.is_empty() or id == "text" or purchases.has(id) or transaction.get("delta") != -int(skill.get("cost", -1)):
				errors.append("设计存档技能收支不一致。")
			purchases[id] = true
	for id in _skill_ids(data):
		if id != "text" and not purchases.has(id): errors.append("设计存档技能缺少实际扣款。")
	if purchases.size() != _skill_ids(data).size() - 1: errors.append("设计存档技能与扣款数不一致。")
	return errors

func restore(data: Dictionary, events: Array = [], variants: Array = [], economy: Dictionary = {}) -> PackedStringArray:
	var errors := validate_payload(data, events, variants, economy)
	if not errors.is_empty(): return errors
	_state = _canonical(data)
	return errors

func migrate(events: Array, variants: Array) -> void:
	# Rebuild new inventory from old recorded sources, never reward currency again.
	reset()
	for variant: Dictionary in variants:
		if variant.get("controlled", false) and variant.get("creator", "") == "player": record_publish(variant)
	for event: Dictionary in events:
		if event.get("acknowledged", false): claim_event(event)

func _skill_ids(data: Dictionary) -> Array:
	return data.get("unlocked_skills", []) if data.get("unlocked_skills") is Array else []

func _empty_bottle(slot: int) -> Dictionary:
	return {"slot":slot, "state":"empty", "solute_id":"", "solvent_id":"", "context_id":""}

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func _canonical(value: Variant) -> Variant:
	# JSON numbers are floats; design quantities and indexes are integral.
	if value is float and _integer(value): return int(value)
	if value is StringName: return String(value)
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry in value: result.append(_canonical(entry))
		return result
	return value

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
