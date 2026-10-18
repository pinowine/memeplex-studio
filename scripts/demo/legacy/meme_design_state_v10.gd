extends RefCounted

const DEFAULT_RULES = preload("res://content/demo/design_rules_v10.tres")
const LEGACY_RULES = preload("res://content/demo/design_rules_v5.tres")
const LegacyDesign = preload("res://scripts/demo/legacy/meme_design_state_v5.gd")
const PreviousDesign = preload("res://scripts/demo/legacy/meme_design_state_v6.gd")
const PREVIOUS_RULES = preload("res://content/demo/design_rules_v6.tres")
const QUARTER_RULES = preload("res://content/demo/design_rules_v8.tres")
const SLICE_LEGACY_RULES = preload("res://content/demo/design_rules_v9.tres")
const SliceLegacyDesign = preload("res://scripts/demo/legacy/meme_design_state_v9.gd")
const RECORD_LIMIT := 65536
var catalog: Resource
var rules: Resource
var _state: Dictionary = {}
var _layer_repeat := false

func _reset_layers() -> void:
	_state.context_resource_inventory = {}
	_state.context_layers = {}
	_state.layer_records = []
	_state.axis_requests = []
	_state.layers_initialized = false
	for entry: Dictionary in rules.context_definitions.entries:
		_state.context_resource_inventory[str(entry.id)] = int(entry.initial_count)
	for index in 5:
		var layer: String = ["language", "group", "topics", "stance", "pragmatic"][index]
		if index < 3:
			var slots: Array = []
			var origins: Array = []
			for slot in (3 if index == 2 else 1):
				slots.append({})
				origins.append("")
			_state.context_layers[layer] = {"slots":slots,"origins":origins,"depth":float(rules.context_depths[index])}
		else:
			_state.context_layers[layer] = {"origin":[0.0,0.0],"current":[0.0,0.0],"offsets":[0,0],"known":false,"depth":float(rules.context_depths[index])}

func _preset_context_base(id: String) -> Dictionary:
	var preset: Resource = catalog.find_preset(id)
	var base := {"language_id":str(catalog.groups[0].language_id),"group_id":str(catalog.groups[0].id),
		"topic_ids":["cost_of_living"],"political_position":[0.0,0.0],"pragmatic_position":[0.0,0.0],"political_known":false}
	return _canonical(preset.to_draft(base))

func _context_id(kind: String, value: String) -> String:
	for entry: Dictionary in rules.context_definitions.entries:
		if str(entry.kind) == kind and str(entry.value) == value: return str(entry.id)
	return ""

func _initialize_layers(base: Dictionary) -> PackedStringArray:
	base = _canonical(base)
	for pair in [["language","language_id"],["group","group_id"]]:
		var id := _context_id(pair[0],str(base.get(pair[1],"")))
		if id.is_empty() or _context_available(id)-_installed_context(id) <= 0: return PackedStringArray(["预设缺少可用的语言或群体语境资源。"])
		_state.context_layers[pair[0]].slots[0] = {"resource_id":id,"source":_context_unit_source(id)}
		_state.context_layers[pair[0]].origins[0] = id
	var topics: Variant = base.get("topic_ids",[])
	if not topics is Array or topics.size() > 3: return PackedStringArray(["预设话题超出三个槽位。"])
	for index in topics.size():
		var id := _context_id("topic",str(topics[index]))
		if id.is_empty() or _installed_context(id) > 0 or _context_available(id) <= 0: return PackedStringArray(["预设话题无效、重复或库存不足。"])
		_state.context_layers.topics.slots[index] = {"resource_id":id,"source":_context_unit_source(id)}
		_state.context_layers.topics.origins[index] = id
	for pair in [["stance","political_position"],["pragmatic","pragmatic_position"]]:
		var point: Variant = base.get(pair[1],[0.0,0.0])
		if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]) or absf(float(point[0])) > 1 or absf(float(point[1])) > 1: return PackedStringArray(["预设二维语境坐标无效。"])
		_state.context_layers[pair[0]].origin = point.duplicate()
		_state.context_layers[pair[0]].current = point.duplicate()
		_state.context_layers[pair[0]].known = bool(base.get("political_known",false)) if pair[0] == "stance" else true
	_state.layers_initialized = true
	return _apply_layers(base)

func _installed_context(id: String) -> int:
	var count := 0
	for layer in ["language","group","topics"]:
		for slot: Dictionary in _state.context_layers[layer].slots:
			if str(slot.get("resource_id","")) == id: count += 1
	return count

func _context_available(id: String) -> int:
	var entry: Dictionary = rules.context_resource(id)
	return maxi(0,int(_state.context_resource_inventory.get(id,0))-_private_count(str(entry.get("kind","")),id))

func _context_sources(id: String) -> Array:
	var entry: Dictionary = rules.context_resource(id)
	var count: int = int(entry.get("initial_count",0))
	var result: Array = [{"source_instance_id":"initial","definition_id":"","preset_id":"","kind":str(entry.get("kind","")),"id":id,"count":count}]
	for source: Dictionary in _state.inventory_sources:
		if source.id == id and source.kind == str(entry.get("kind","")) and _material_requested(str(source.source_instance_id),str(source.kind),id): result.append(source.duplicate(true))
	return result

func _context_unit_source(id: String) -> Dictionary:
	var used := {}
	for layer in ["language","group","topics"]:
		for slot: Dictionary in _state.context_layers[layer].slots:
			if slot.get("source") is Dictionary: used[str(slot.source.get("unit_id",""))] = true
	for source: Dictionary in _context_sources(id):
		for index in int(source.count):
			var key := "%s:%s:%s:%d" % [source.source_instance_id,source.kind,id,index]
			if not used.has(key):
				var result := source.duplicate(true)
				result.unit_id = key
				return result
	return {}

func _locked_tokens(layer: String) -> int:
	var offsets: Array = _state.context_layers[layer].offsets
	return absi(int(offsets[0]))+absi(int(offsets[1]))

func _perform_layer(action: String, params: Dictionary) -> PackedStringArray:
	_layer_repeat = false
	var layer := str(params.get("layer",""))
	if not _state.layers_initialized or not _state.context_layers.has(layer): return PackedStringArray(["请先确认开局模因。"])
	if action == "set_context_depth":
		if not _number(params.get("depth")) or float(params.depth) < 0 or float(params.depth) > 1: return PackedStringArray(["切片深度需在 0—1 范围内。"])
		_state.context_layers[layer].depth = float(params.depth)
		return PackedStringArray()
	if not params.get("base") is Dictionary: return PackedStringArray(["语境配置需要自己的待发布草稿。"])
	if action in ["install_context","remove_context"]:
		if layer not in ["language","group","topics"] or not _integer(params.get("slot")) or int(params.slot) < 0 or int(params.slot) >= _state.context_layers[layer].slots.size(): return PackedStringArray(["语境槽位无效。"])
		var slot := int(params.slot)
		if action == "remove_context":
			if _state.context_layers[layer].slots[slot].is_empty(): return PackedStringArray(["该语境槽为空。"])
			_state.context_layers[layer].slots[slot] = {}
		else:
			var id := str(params.get("resource_id",""))
			var entry: Dictionary = rules.context_resource(id)
			if not _state.context_layers[layer].slots[slot].is_empty(): return PackedStringArray(["请先移除原语境资源。"])
			if str(entry.get("kind","")) != ("topic" if layer == "topics" else layer) or _context_available(id)-_installed_context(id) <= 0: return PackedStringArray(["没有可用且匹配的语境资源。"])
			if layer == "topics" and _installed_context(id) > 0: return PackedStringArray(["同一话题不能重复占槽。"])
			var source := _context_unit_source(id)
			if source.is_empty(): return PackedStringArray(["语境资源来源不可用。"])
			_state.context_layers[layer].slots[slot] = {"resource_id":id,"source":source}
	else:
		if layer not in ["stance","pragmatic"] or str(params.get("axis","")) not in ["x","y"] or not _integer(params.get("direction")) or int(params.direction) not in [-1,1]: return PackedStringArray(["二维移动每次只接受一个轴的一步。"])
		if not params.get("request_id") is String or params.request_id.is_empty() or params.request_id.length() > 128: return PackedStringArray(["二维移动需要有限请求标识。"])
		var request := {"request_id":str(params.request_id),"layer":layer,"axis":str(params.axis),"direction":int(params.direction)}
		for previous: Dictionary in _state.axis_requests:
			if previous.request_id == request.request_id:
				_layer_repeat = true
				return PackedStringArray() if previous == request else PackedStringArray(["请求标识已用于另一项移动。"])
		var axis := 0 if str(params.axis) == "x" else 1
		var data: Dictionary = _state.context_layers[layer]
		var old := int(data.offsets[axis])
		var next := old+int(params.direction)
		var origin := float(data.origin[axis])
		var minimum := int(floor((-1.0-origin)/rules.axis_step+0.000001))
		var maximum := int(ceil((1.0-origin)/rules.axis_step-0.000001))
		if next < minimum or next > maximum: return PackedStringArray(["坐标已到达边界。"])
		var cost := absi(next)-absi(old)
		var token_id := _axis_token(layer,str(params.axis),1 if next > 0 else -1)
		if cost > 0 and _context_available(token_id)-_locked_token(token_id) < cost: return PackedStringArray(["没有足够的对应端筹码。"])
		data.offsets[axis] = next
		data.current[axis] = float(Vector2(clampf(origin+float(next)*rules.axis_step,-1.0,1.0),0.0).x)
		data.known = true
		_state.axis_requests.append(request)
	return _apply_layers(params.base)

func _layer_fields() -> Dictionary:
	var result := {"language_id":"","group_id":"","topic_ids":[],"political_position":_state.context_layers.stance.current.duplicate(),"pragmatic_position":_state.context_layers.pragmatic.current.duplicate(),"political_known":_state.context_layers.stance.known}
	for pair in [["language","language_id"],["group","group_id"],["topics","topic_ids"]]:
		for slot: Dictionary in _state.context_layers[pair[0]].slots:
			if slot.is_empty(): continue
			var value: String = str(rules.context_resource(str(slot.resource_id)).value)
			if pair[0] == "topics": result.topic_ids.append(value)
			else: result[pair[1]] = value
	return result

func _apply_layers(base: Dictionary) -> PackedStringArray:
	var draft: Dictionary = _canonical(base)
	if not author_marks_valid(draft) or not context_sources_valid(draft.get("context_sources",[])): return PackedStringArray(["草稿来源记录无效。"])
	var fields := _layer_fields()
	draft.merge(fields,true)
	var record := {"index":_state.layer_records.size(),"fields":fields.duplicate(true)}
	_state.layer_records.append(record)
	draft.context_layer_record = record.duplicate(true)
	_state.context_draft = draft
	return PackedStringArray()

func layer_errors(base: Dictionary) -> PackedStringArray:
	if rules.definition_version < 5 or not _state.layers_initialized: return PackedStringArray()
	base = _canonical(base)
	var fields: Dictionary = _canonical(_layer_fields())
	for key in fields:
		if base.get(key) != fields[key]: return PackedStringArray(["草稿语境与脑切片配置不一致。"])
	return PackedStringArray()

func _snapshot_layers(result: Dictionary) -> void:
	result.next_axis_request_index = _state.axis_requests.size()+1
	result.context_layers = _state.context_layers.duplicate(true)
	result.resources = []
	result.available_context_inventory = {}
	for entry: Dictionary in rules.context_definitions.entries:
		var id := str(entry.id)
		var row := entry.duplicate(true)
		row.resource_id = id
		row.count = int(_state.context_resource_inventory.get(id,0))
		row.installed = _installed_context(id)
		row.available = maxi(0,_context_available(id)-int(row.installed))
		row.source_records = _context_sources(id)
		result.available_context_inventory[id] = row.available
		result.resources.append(row)
	for layer in ["language","group","topics"]:
		for index in result.context_layers[layer].slots.size():
			var slot: Dictionary = result.context_layers[layer].slots[index]
			if slot.is_empty(): continue
			var entry: Dictionary = rules.context_resource(str(slot.resource_id)).duplicate(true)
			entry.merge(slot,true)
			result.context_layers[layer].slots[index] = entry
	result.token_balances = {"stance_token":0,"pragmatic_token":0}
	result.context_token_balances = {}
	result.token_inventory = {}
	result.token_accounts = {}
	for entry: Dictionary in rules.context_definitions.entries:
		if str(entry.kind) not in ["stance_token","pragmatic_token"]: continue
		var id := str(entry.id)
		var locked := _locked_token(id)
		var available := maxi(0,_context_available(id)-locked)
		result.context_token_balances[id] = available
		result.token_inventory[id] = int(_state.context_resource_inventory[id])
		result.token_accounts[id] = {"owned":result.token_inventory[id],"available":available,"locked":locked}
		result.token_balances[str(entry.kind)] += available
		result.available_context_inventory[id] = available
		for row: Dictionary in result.resources:
			if row.id == id: row.available = available; row.installed = locked
	for layer in ["stance","pragmatic"]:
		result.context_layers[layer].step = rules.axis_step
		result.context_layers[layer].token_kind = layer+"_token"
		result.context_layers[layer].token_ids = {"x_negative":_axis_token(layer,"x",-1),"x_positive":_axis_token(layer,"x",1),"y_negative":_axis_token(layer,"y",-1),"y_positive":_axis_token(layer,"y",1)}
		result.context_layers[layer].axis_labels = {"x_negative":"自由","x_positive":"威权","y_negative":"平等","y_positive":"等级"} if layer == "stance" else {"x_negative":"真诚","x_positive":"反讽","y_negative":"支持","y_positive":"反对"}

func token_balance(id: String) -> int:
	return maxi(0,_context_available(id)-_locked_token(id))

func _axis_token(layer: String, axis: String, direction: int) -> String:
	for entry: Dictionary in rules.context_definitions.entries:
		if str(entry.kind) == layer+"_token" and str(entry.get("axis","")) == axis and int(entry.get("direction",0)) == direction: return str(entry.id)
	return ""

func _locked_token(id: String) -> int:
	var entry: Dictionary = rules.context_resource(id)
	if str(entry.get("kind","")) not in ["stance_token","pragmatic_token"]: return 0
	var layer := "stance" if str(entry.kind) == "stance_token" else "pragmatic"
	var axis := 0 if str(entry.axis) == "x" else 1
	var offset := int(_state.context_layers[layer].offsets[axis])
	return absi(offset) if signi(offset) == int(entry.direction) else 0

func _import_slice_state(params: Dictionary, source: Dictionary) -> PackedStringArray:
	if not _state.operations.is_empty() or not params.get("payload") is Dictionary or not params.get("variant_ids") is Array or not source.has_all(["events","variants","economy"]): return PackedStringArray(["旧设计导入记录无效。"])
	var variants: Array = []
	for variant: Dictionary in source.variants:
		if str(variant.id) in params.variant_ids: variants.append(variant)
	if variants.size() != params.variant_ids.size(): return PackedStringArray(["旧设计版本来源丢失。"])
	var economy: Dictionary = source.economy.duplicate(true)
	economy.transactions = economy.get("transactions",[]).filter(func(entry: Dictionary)->bool: return not str(entry.get("reason","")).begins_with("技能解锁：") or str(entry.reason).trim_prefix("技能解锁：") in params.payload.get("unlocked_skills",[]))
	var reader: RefCounted = SliceLegacyDesign.new(catalog,SLICE_LEGACY_RULES)
	var errors: PackedStringArray = reader.restore(params.payload,source.events,variants,economy)
	if not errors.is_empty(): return errors
	_state = reader.payload()
	_state.design_version = 5
	_state.rules_signature = rules.signature()
	_state.operations = []
	_reset_layers()
	var base: Dictionary = params.get("base",{}).duplicate(true)
	if base.is_empty() and not variants.is_empty():
		var variant: Dictionary = variants[-1]
		base = {"language_id":str(variant.get("language_id","zh")),"group_id":str(catalog.groups[0].id),"topic_ids":variant.get("topic_ids",["cost_of_living"]),"political_position":variant.get("political_position",[0,0]),"pragmatic_position":variant.get("pragmatic_position",[0,0]),"political_known":variant.get("political_known",false)}
	if base.is_empty() and not str(_state.starter_preset_id).is_empty(): base = _preset_context_base(str(_state.starter_preset_id))
	return _initialize_layers(base) if not base.is_empty() else PackedStringArray()

func _init(content: Resource = null, definitions: Resource = null) -> void:
	catalog = content
	rules = definitions if definitions != null else DEFAULT_RULES
	reset()

func reset() -> void:
	_state = {"design_version":5 if rules.definition_version >= 5 else (4 if rules.definition_version >= 4 else 3), "rules_signature":rules.signature(), "starter_preset_id":"",
		"core_kernel_id":"", "core_preset_id":"",
		"module_inventory":{}, "module_slots":[], "module_contents":[], "module_positions":[], "connections":[], "solute_inventory":{},
		"ground_inventory":{}, "solvent_inventory":{}, "context_inventory":{}, "bottles":[],
		"solute_sources":{}, "ground_sources":{}, "context_sources":{}, "inventory_sources":[], "solvent_reserve":{},
		"context_draft":{}, "context_application":"", "applied_context_sources":[],
		"current_publish_index":0, "skill_applications":[], "skill_application":"", "module_records":[], "module_application":"",
		"mortar":_empty_mortar(), "chamber_slots":[], "chamber_solvents":{},
		"chamber_pending":[], "chamber_dissolved":[], "flask_solids":[], "mass_serial":0,
		"discarded_sources":[], "legacy_discarded_units":0, "event_material_claims":[],
		"stirred":false, "lamp_cycles":0, "last_distillation":[], "unlocked_skills":["text"],
		"claimed_events":[], "inventory_log":[], "operations":[]}
	if rules.definition_version >= 4:
		_state.liquid_requests = []
		_state.evaporated_solvents = {}
	for index in rules.module_slots:
		_state.module_slots.append("")
		_state.module_contents.append("")
		_state.module_positions.append(_default_module_position(index))
	for index in rules.bottle_slots: _state.bottles.append(_empty_bottle(index))
	for entry in rules.solutes:
		_state.solute_inventory[str(entry.id)] = rules.initial_solute_count
		_state.ground_inventory[str(entry.id)] = 0
		_state.solute_sources[str(entry.id)] = []
		_state.ground_sources[str(entry.id)] = []
		for index in rules.initial_solute_count: _state.solute_sources[str(entry.id)].append({"source_instance_id":"initial", "definition_id":"", "preset_id":"", "kind":"solute", "id":str(entry.id), "count":1})
	for entry in rules.solvents:
		_state.solvent_inventory[str(entry.id)] = int(entry.get("initial_count", rules.initial_solvent_count))*_liquid_scale()
		_state.solvent_reserve[str(entry.id)] = 0
		if rules.definition_version >= 4: _state.evaporated_solvents[str(entry.id)] = 0

	if rules.definition_version >= 5: _reset_layers()

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
	if rules.definition_version >= 5 and action in ["grind", "mortar_load", "grind_stroke", "take_ground", "take_ground_fill", "fill", "pour", "pour_solvent", "pour_powder", "put", "stir", "lamp", "take", "apply_context", "take_apply_context", "discard", "discard_solid", "discard_pending"]: return PackedStringArray(["培养已改为脑切片配置；旧化学动作不再可用。"])
	if action in ["claim", "publish", "unlock", "legacy_import", "sync_draft", "request_material", "initialize_context"]: return PackedStringArray(["该动作只能由模拟账本提交。"])
	var pristine := _state.duplicate(true)
	var errors := _perform(action, params)
	if not errors.is_empty(): _state = pristine
	return errors

func _perform(action: String, params: Dictionary, source: Dictionary = {}) -> PackedStringArray:
	params = _canonical(params)
	if rules.definition_version >= 5 and action in ["grind", "mortar_load", "grind_stroke", "take_ground", "take_ground_fill", "fill", "pour", "pour_solvent", "pour_powder", "put", "stir", "lamp", "take", "apply_context", "take_apply_context", "discard", "discard_solid", "discard_pending"]: return PackedStringArray(["旧化学操作只用于认证历史回放。"])
	var errors := PackedStringArray()
	if _state.operations.size() >= RECORD_LIMIT: return PackedStringArray(["设计操作记录已达有限上限。"])
	var id := str(params.get("solute_id", ""))
	var slot := -1
	if action in ["fill", "put", "take", "install_module", "remove_module", "edit_module_content", "move_module", "take_ground_fill", "take_apply_context", "pour_powder"] or (action == "discard" and params.has("slot")):
		var limit: int = rules.module_slots if action in ["install_module", "remove_module", "edit_module_content", "move_module"] else rules.bottle_slots
		if action in ["take", "take_apply_context"] and params.has("solid_id"):
			slot = -1
		elif not _integer(params.get("slot")) or int(params.slot) < 0 or int(params.slot) >= limit:
			return PackedStringArray(["槽位超出有限范围。"])
		else:
			slot = int(params.slot)
	if rules.definition_version >= 5 and action in ["install_context", "remove_context", "move_context_axis", "set_context_depth"]:
		errors = _perform_layer(action, params)
		if errors.is_empty() and not _layer_repeat:
			_state.operations.append({"action":action,"params":params.duplicate(true)})
		return errors
	match action:
		"choose_starter":
			var preset_id := str(params.get("preset_id", ""))
			if preset_id not in rules.starter_presets or catalog == null or catalog.find_preset(preset_id) == null:
				return PackedStringArray(["开局预设未登记。"])
			if not str(_state.starter_preset_id).is_empty():
				return errors if _state.starter_preset_id == preset_id else PackedStringArray(["本局开局预设已确认。"])
			_state.starter_preset_id = preset_id
			_state.core_preset_id = preset_id
			_state.core_kernel_id = str(catalog.find_preset(preset_id).kernel_id)
			_grant_module(str(catalog.find_preset(preset_id).kernel_id))
			if rules.definition_version >= 5:
				var expected: Dictionary = _preset_context_base(preset_id)
				var base: Dictionary = params.get("base", expected)
				for key in expected:
					if _canonical(base.get(key)) != _canonical(expected[key]): return PackedStringArray(["开局语境原点必须来自已登记预设。"] )
				errors = _initialize_layers(base)
				if not errors.is_empty(): return errors
		"install_module":
			var module_id := str(params.get("module_id", ""))
			if rules.find("modules", module_id).is_empty() or _available_count("module",module_id) <= 0:
				return PackedStringArray(["仓库中没有该模块。"])
			var used := 0
			for index in _state.module_slots.size():
				if index != slot and _state.module_slots[index] == module_id: used += 1
			if used >= _available_count("module",module_id): return PackedStringArray(["已搬出的模块数量不足，不能复制纸片。"])
			if not params.get("base") is Dictionary: return PackedStringArray(["表达补丁需要自己的待发布草稿。"])
			var content: Variant = params.get("content", rules.find("modules", module_id).content)
			if not content is String or content.strip_edges().is_empty() or content.length() > 2048: return PackedStringArray(["补丁内容需为有限非空文本。"])
			_state.module_slots[slot] = module_id
			_state.module_contents[slot] = content
			errors = _apply_modules(params.base)
			if not errors.is_empty(): return errors
		"remove_module":
			if str(_state.module_slots[slot]).is_empty(): return PackedStringArray(["该槽位没有表达补丁。"])
			if not params.get("base") is Dictionary: return PackedStringArray(["移除补丁需要自己的待发布草稿。"])
			_state.module_slots[slot] = ""
			_state.module_contents[slot] = ""
			_state.module_positions[slot] = _default_module_position(slot)
			_state.connections = _state.connections.filter(func(edge: Dictionary) -> bool: return int(edge.from) != slot and int(edge.to) != slot)
			errors = _apply_modules(params.base)
			if not errors.is_empty(): return errors
		"edit_module_content":
			var content: Variant = params.get("content")
			if str(_state.module_slots[slot]).is_empty() or not params.get("base") is Dictionary or not content is String or content.strip_edges().is_empty() or content.length() > 2048: return PackedStringArray(["需要已安装补丁、自己的草稿与有限非空文本。"])
			_state.module_contents[slot] = content
			errors = _apply_modules(params.base)
			if not errors.is_empty(): return errors
		"move_module":
			var point: Variant = params.get("position")
			if str(_state.module_slots[slot]).is_empty() or not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]) or float(point[0]) < 0 or float(point[0]) > 1 or float(point[1]) < 0 or float(point[1]) > 1: return PackedStringArray(["只能移动纸内已安装的补丁神经元。"])
			_state.module_positions[slot] = point.duplicate()
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
		"grind", "mortar_load":
			if not _state.solute_inventory.has(id) or _available_count("solute",id) <= 0: return PackedStringArray(["请先从事件纸搬出这份溶质。"])
			if int(_state.mortar.count) != 0: return PackedStringArray(["请先取出或废弃研钵中的材料。"])
			_state.solute_inventory[id] -= 1
			var source_index := _available_source_index(_state.solute_sources[id],"solute",id)
			var provenance: Dictionary = _state.solute_sources[id][source_index]
			_state.solute_sources[id].remove_at(source_index)
			_state.mortar = {"solute_id":id,"count":1,"state":"raw","progress":0.0,"reversals":0,"direction":0,"quantity_units":rules.mass_units_per_solute,"source":_batch_source(provenance,rules.mass_units_per_solute)}
		"grind_stroke":
			if str(_state.mortar.state) != "raw": return PackedStringArray(["研钵中需要待磨的原块。"])
			var direction: Variant = params.get("direction")
			var distance: Variant = params.get("distance")
			if not _integer(direction) or int(direction) not in [-1,1] or not _number(distance) or float(distance) <= 0 or float(distance) > rules.grinding_stroke_limit: return PackedStringArray(["研杵行程超出有效摆动范围。"])
			if int(_state.mortar.direction) == int(direction): return PackedStringArray(["请反向摆动研杵。"])
			if int(_state.mortar.direction) != 0: _state.mortar.reversals += 1
			_state.mortar.direction = int(direction)
			_state.mortar.progress = minf(rules.grinding_distance,float(_state.mortar.progress)+float(distance))
			if float(_state.mortar.progress) >= rules.grinding_distance and int(_state.mortar.reversals) >= rules.grinding_reversals: _state.mortar.state = "ground"
		"take_ground":
			if str(_state.mortar.state) != "ground": return PackedStringArray(["请先摆动研杵磨好粉末。"])
			id = str(_state.mortar.solute_id)
			_state.ground_inventory[id] += 1
			_state.ground_sources[id].append(_state.mortar.source.duplicate(true))
			_state.mortar = _empty_mortar()
		"take_ground_fill":
			if _state.bottles[slot].state != "empty" or str(_state.mortar.state) != "ground": return PackedStringArray(["需要磨好的粉末和一个空瓶。"])
			_state.bottles[slot] = _filled_bottle(slot,str(_state.mortar.solute_id),_state.mortar.source)
			_state.mortar = _empty_mortar()
		"fill":
			if _state.bottles[slot].state != "empty": return PackedStringArray(["每瓶只容纳一种溶质，请先倒出或废弃。"])
			if not _state.ground_inventory.has(id) or int(_state.ground_inventory[id]) <= 0: return PackedStringArray(["请先磨碎并取出该溶质。"])
			_state.ground_inventory[id] -= 1
			_state.bottles[slot] = _filled_bottle(slot,id,_state.ground_sources[id].pop_front())
		"pour", "pour_solvent":
			var solvent_id := str(params.get("solvent_id", params.get("id","")))
			var amount: Variant = params.get("amount", rules.solvent_dose)
			var units := 0
			if rules.definition_version >= 4 and params.has("units"):
				if params.has("amount") or not _integer(params.units) or int(params.units) <= 0: return PackedStringArray(["倾倒量需为正整数，不能混用两种计量。"])
				units = int(params.units)
			else:
				if not _integer(amount) or int(amount) != rules.solvent_dose: return PackedStringArray(["旧计量只接受一份溶剂。"])
				units = int(amount)*_liquid_scale()
			var request_id := ""
			if rules.definition_version >= 4 and params.has("request_id"):
				if not params.request_id is String or params.request_id.is_empty() or params.request_id.length() > 128: return PackedStringArray(["倾倒请求标识无效。"])
				request_id = params.request_id
				for request: Dictionary in _state.liquid_requests:
					if request.request_id != request_id: continue
					return errors if request.id == solvent_id and request.units == units else PackedStringArray(["倾倒请求已使用，不能改写其用量。"])
			if not _state.solvent_inventory.has(solvent_id) or units > _solvent_capacity(solvent_id) or units > int(_state.solvent_inventory[solvent_id]) or _available_count("solvent",solvent_id) < units: return PackedStringArray(["瓶中已搬出的溶剂不足。"])
			if rules.definition_version >= 4 and _chamber_liquid_total()+units > rules.flask_liquid_capacity_units: return PackedStringArray(["烧瓶没有足够的剩余容量。"])
			_state.solvent_inventory[solvent_id] -= units
			_state.chamber_solvents[solvent_id] = int(_state.chamber_solvents.get(solvent_id, 0)) + units
			var refill := mini(int(_state.solvent_reserve[solvent_id]), _solvent_capacity(solvent_id) - int(_state.solvent_inventory[solvent_id]))
			_state.solvent_inventory[solvent_id] += refill
			_state.solvent_reserve[solvent_id] -= refill
			if not request_id.is_empty(): _state.liquid_requests.append({"request_id":request_id,"id":solvent_id,"units":units})
			_state.stirred = false
		"pour_powder":
			var units: Variant = params.get("units")
			var bottle: Dictionary = _state.bottles[slot]
			if bottle.state != "filled" or not _integer(units) or int(units) <= 0 or int(units) > int(bottle.quantity_units): return PackedStringArray(["只能从装粉瓶倒出其剩余粉末。"])
			var provenance: Dictionary = bottle.source.duplicate(true)
			provenance.portion_units = int(units)
			_append_portion(_state.chamber_pending,{"solute_id":bottle.solute_id,"quantity_units":int(units),"source":provenance,"via":{}})
			bottle.quantity_units -= int(units)
			bottle.source.portion_units = int(bottle.quantity_units)
			if int(bottle.quantity_units) == 0: _state.bottles[slot] = _empty_bottle(slot)
			_state.stirred = false
		"put":
			return PackedStringArray(["请拿起粉末瓶，靠近瓶口倾倒粉末。"])
		"stir":
			errors = _dissolve_pending()
			if not errors.is_empty(): return errors
		"lamp":
			if not _state.stirred or _state.chamber_dissolved.is_empty() or _state.chamber_solvents.is_empty(): return PackedStringArray(["点灯前需加入材料并搅拌溶液。"])
			var sequence: Array[Dictionary] = []
			for solvent_id in _state.chamber_solvents:
				sequence.append({"solvent_id":str(solvent_id),"boiling_order":int(rules.find("solvents",str(solvent_id)).boiling_order),"amount":int(_state.chamber_solvents[solvent_id])})
			sequence.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.boiling_order < b.boiling_order or (a.boiling_order == b.boiling_order and a.solvent_id < b.solvent_id))
			for portion: Dictionary in _state.chamber_dissolved:
				var context_parts := PackedStringArray()
				for entry: Dictionary in sequence:
					if int(portion.via.get(entry.solvent_id,0)) > 0: context_parts.append(entry.solvent_id)
				_state.mass_serial += 1
				_state.flask_solids.append({"id":"solid_%04d" % int(_state.mass_serial),"solute_id":portion.solute_id,"context_id":str(portion.solute_id)+"@"+"+".join(context_parts),"quantity_units":portion.quantity_units,"source":portion.source.duplicate(true)})
			_state.last_distillation = sequence
			if rules.definition_version >= 4:
				for solvent_id in _state.chamber_solvents: _state.evaporated_solvents[solvent_id] += int(_state.chamber_solvents[solvent_id])
			_state.chamber_solvents.clear()
			_state.chamber_dissolved.clear()
			_state.chamber_slots.clear()
			_state.stirred = false
			_state.lamp_cycles += 1
		"take":
			var solid_index := _solid_index(params,slot)
			if solid_index < 0: return PackedStringArray(["溶剂尚未蒸干，不能取出固体。"])
			var solid: Dictionary = _state.flask_solids[solid_index]
			_state.context_inventory[str(solid.context_id)] = int(_state.context_inventory.get(str(solid.context_id),0)) + 1
			if not _state.context_sources.has(str(solid.context_id)): _state.context_sources[str(solid.context_id)] = []
			_state.context_sources[str(solid.context_id)].append(solid.source.duplicate(true))
			_state.flask_solids.remove_at(solid_index)
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
			_state.context_application = "%s已融入表达。" % str(rules.find("solutes", context_id.get_slice("@", 0)).title)
		"take_apply_context":
			var solid_index := _solid_index(params,slot)
			if solid_index < 0 or not params.get("base") is Dictionary: return PackedStringArray(["只有蒸干后的固体可拖入自己的模因。"])
			var solid: Dictionary = _state.flask_solids[solid_index]
			var solute: Dictionary = rules.find("solutes",str(solid.solute_id))
			var draft := _effect_draft(params.base,_portion_effects(solute.get("effects",[]),solid.source))
			if draft.is_empty(): return PackedStringArray(["作者草稿或材料来源不合法。"])
			var provenance: Dictionary = solid.source.duplicate(true)
			var sources: Array = draft.get("context_sources",[]).duplicate(true)
			sources.append(provenance)
			draft.context_sources = sources
			_state.applied_context_sources.append(provenance)
			_state.context_draft = draft
			_state.context_application = "%s已融入表达。" % str(solute.title)
			_state.flask_solids.remove_at(solid_index)
		"apply_skill":
			var skill_id := str(params.get("skill_id", ""))
			var skill: Dictionary = rules.find("skills", skill_id)
			if skill_id not in _state.unlocked_skills or skill.get("draft_effects", []).is_empty(): return PackedStringArray(["该能力未解锁或没有可应用的草稿作用。"])
			if skill_applied(skill_id): return PackedStringArray(["本轮待发布草稿已应用该能力，不能重复堆叠。"])
			if not params.get("base") is Dictionary: return PackedStringArray(["应用能力需要合法的作者草稿。"])
			var draft := _effect_draft(params.base, skill.draft_effects)
			if draft.is_empty(): return PackedStringArray(["作者草稿字段或固体来源不合法。"])
			var application := {"publish_index":int(_state.current_publish_index), "skill_id":skill_id, "effects":_deltas(params.base, draft, skill.draft_effects)}
			var marks: Array = draft.get("skill_effects", []).duplicate(true)
			marks.append(application.duplicate(true))
			draft.skill_effects = marks
			_state.skill_applications.append(application)
			_state.context_draft = draft
			_state.skill_application = "%s正帮你的表达走得更远。" % str(skill.title)
		"discard":
			if slot >= 0:
				if _state.bottles[slot].state == "empty": return PackedStringArray(["空瓶无可废弃材料。"])
				_state.discarded_sources.append(_state.bottles[slot].source.duplicate(true))
				_state.bottles[slot] = _empty_bottle(slot)
				_state.chamber_slots.erase(slot)
				_state.stirred = false
			else:
				var inventory := str(params.get("source", "ground"))
				if inventory == "mortar":
					if int(_state.mortar.count) == 0: return PackedStringArray(["研钵是空的。"])
					_state.discarded_sources.append(_state.mortar.source.duplicate(true))
					_state.mortar = _empty_mortar()
				elif inventory in ["ground", "solute", "context"]:
					var key: String = {"ground":"ground_inventory", "solute":"solute_inventory", "context":"context_inventory"}[inventory]
					id = str(params.get("context_id", id))
					if int(_state[key].get(id, 0)) <= 0: return PackedStringArray(["没有可废弃的材料。"])
					if inventory == "solute" and _available_count("solute",id) <= 0: return PackedStringArray(["封存的物资不能废弃。"])
					_state[key][id] -= 1
					var sources: Array = _state[{"ground":"ground_sources", "solute":"solute_sources", "context":"context_sources"}[inventory]][id]
					var source_index := _available_source_index(sources,"solute",id) if inventory == "solute" else 0
					_state.discarded_sources.append(sources[source_index].duplicate(true))
					sources.remove_at(source_index)
				else: return PackedStringArray(["废弃来源未登记。"])
		"request_material":
			errors = _request_material(params,source)
			if not errors.is_empty(): return errors
		"discard_solid":
			var solid_index := _solid_index(params,-1)
			if solid_index < 0: return PackedStringArray(["烧瓶中没有这份固体。"])
			_state.discarded_sources.append(_state.flask_solids[solid_index].source.duplicate(true))
			_state.flask_solids.remove_at(solid_index)
		"discard_pending":
			var pending_id := str(params.get("batch_id",""))
			var found := false
			for index in range(_state.chamber_pending.size()-1,-1,-1):
				if str(_state.chamber_pending[index].source.batch_id) == pending_id:
					_state.discarded_sources.append(_state.chamber_pending[index].source.duplicate(true))
					_state.chamber_pending.remove_at(index)
					found = true
			if not found: return PackedStringArray(["烧瓶中没有这份未溶粉末。"])
		"claim":
			var instance_id := str(params.get("instance_id", ""))
			if instance_id.is_empty() or source.is_empty() or not source.get("acknowledged", false): return PackedStringArray(["只能领取已确认的真实事件纸奖励。"])
			if instance_id in _state.claimed_events: return errors
			var rewards: Variant = source.get("design_rewards", [])
			if not rewards is Array: return PackedStringArray(["事件物资字段类型错误。"])
			for reward: Variant in rewards:
				if not reward is Dictionary or str(reward.get("kind", "")) not in ["module", "solute", "solvent", "language", "group", "topic", "stance_token", "pragmatic_token"] or not _integer(reward.get("count")) or int(reward.count) < 1:
					return PackedStringArray(["事件物资记录无效。"])
				if rules.reward_resource(str(reward.kind), str(reward.get("id", ""))).is_empty(): return PackedStringArray(["事件物资未登记。"])
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
						var space := _solvent_capacity(reward_id) - int(_state.solvent_inventory[reward_id])
						var filled := mini(count*_liquid_scale(), space)
						_state.solvent_inventory[reward_id] += filled
						_state.solvent_reserve[reward_id] += count*_liquid_scale() - filled
					_:
						_state.context_resource_inventory[reward_id] = int(_state.context_resource_inventory.get(reward_id,0)) + count
				labels.append("%s ×%d" % [str(rules.reward_resource(kind, reward_id).title), count])
			_state.claimed_events.append(instance_id)
			if not labels.is_empty(): _state.inventory_log.append("事件 %s：%s" % [instance_id, "、".join(labels)])
		"publish":
			if source.is_empty() or not source.get("controlled", false) or not source.get("owned", false) or source.get("creator", "") != "player": return PackedStringArray(["只有玩家已发布版本可登记模块。"])
			_grant_module(str(source.kernel_id))
			if str(_state.core_kernel_id).is_empty():
				_state.core_kernel_id = str(source.kernel_id)
				_state.core_preset_id = str(source.get("preset_id", ""))
			_state.current_publish_index += 1
		"unlock":
			var skill_id := str(params.get("skill_id", ""))
			errors = skill_errors(skill_id)
			if not errors.is_empty(): return errors
			_state.unlocked_skills.append(skill_id)
		"legacy_import":
			errors = _import_legacy(params, source)
			if not errors.is_empty(): return errors
		"initialize_context":
			if rules.definition_version < 5 or _state.layers_initialized or int(_state.current_publish_index) <= 0 or not params.get("base") is Dictionary: return PackedStringArray(["初始脑切片不能重复建立。"] )
			errors = _initialize_layers(params.base)
			if not errors.is_empty(): return errors
		"sync_draft":
			if not params.get("base") is Dictionary: return PackedStringArray(["草稿同步类型错误。"])
			var draft := _effect_draft(params.base, [])
			if draft.is_empty(): return PackedStringArray(["草稿同步来源无效。"])
			_state.context_draft = draft
		_:
			return PackedStringArray(["设计动作未登记：" + action])
	_state.operations.append({"action":action, "params":params.duplicate(true)})
	return errors

func _grant_module(kernel_id: String) -> void:
	var id := "module_" + kernel_id
	if rules.find("modules", id).is_empty(): return
	_state.module_inventory[id] = int(_state.module_inventory.get(id, 0)) + 1

func initialize_context(base: Dictionary) -> PackedStringArray:
	return _perform("initialize_context",{"base":base})

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
	var sources: Array = _state.context_sources.get(id,[])
	if sources.is_empty(): return {}
	return _effect_draft(base,_portion_effects(solute.effects,sources[0]))

func _effect_draft(base: Dictionary, effects: Array) -> Dictionary:
	var draft: Dictionary = _canonical(base)
	if not context_sources_valid(draft.get("context_sources", [])): return {}
	if not author_marks_valid(draft): return {}
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

func _deltas(before: Dictionary, after: Dictionary, effects: Array) -> Array:
	var result: Array = []
	for effect: Dictionary in effects:
		var field := str(effect.field)
		result.append({"field":field, "delta":float(after[field]) - float(before[field])})
	return result

func author_marks_valid(draft: Dictionary, state: Dictionary = {}) -> bool:
	var registry: Dictionary = _state if state.is_empty() else _canonical(state)
	var module_records: Array = _canonical(registry.get("module_records", []))
	var applications: Array = _canonical(registry.get("skill_applications", []))
	if draft.has("module_patch_record"):
		if not draft.module_patch_record is Dictionary or _canonical(draft.module_patch_record) not in module_records: return false
	if rules.definition_version >= 5 and draft.has("context_layer_record"):
		if not draft.context_layer_record is Dictionary or _canonical(draft.context_layer_record) not in _canonical(registry.get("layer_records", [])): return false
		var fields: Dictionary = draft.context_layer_record.get("fields",{})
		for key in fields:
			if not draft.has(key): continue
			if key == "political_position" and not bool(fields.get("political_known",false)) and draft[key] is Array and draft[key].is_empty(): continue
			if _canonical(draft[key]) != _canonical(fields[key]): return false
	var marks: Variant = draft.get("skill_effects", [])
	if not marks is Array: return false
	var seen := {}
	for mark: Variant in marks:
		if not mark is Dictionary or _canonical(mark) not in applications: return false
		var key := "%s:%s" % [str(mark.get("publish_index", "")), str(mark.get("skill_id", ""))]
		if seen.has(key): return false
		seen[key] = true
	return true

func skill_applied(id: String) -> bool:
	for application: Dictionary in _state.skill_applications:
		if int(application.publish_index) == int(_state.current_publish_index) and str(application.skill_id) == id: return true
	return false

func _strip_effects(draft: Dictionary, effects: Array) -> void:
	for effect: Dictionary in effects:
		var field := str(effect.field)
		draft[field] = clampf(float(draft[field]) - float(effect.delta), 0.0, 1.0)

func revision_base(base: Dictionary) -> Dictionary:
	var draft: Dictionary = _canonical(base)
	if not author_marks_valid(draft): return {}
	for mark: Dictionary in draft.get("skill_effects", []):
		_strip_effects(draft, mark.get("effects", []))
	draft.erase("skill_effects")
	return draft

func apply_unlocked(base: Dictionary, new_round: bool = false) -> PackedStringArray:
	var pristine := _state.duplicate(true)
	var draft: Dictionary = revision_base(base) if new_round else _canonical(base)
	if draft.is_empty() or not author_marks_valid(draft): return PackedStringArray(["能力应用需要自己的合法草稿记录。"])
	for id in _state.unlocked_skills:
		if rules.find("skills", str(id)).get("draft_effects", []).is_empty() or skill_applied(str(id)): continue
		var errors := _perform("apply_skill", {"skill_id":str(id), "base":draft})
		if not errors.is_empty():
			_state = pristine
			return errors
		draft = _state.context_draft.duplicate(true)
	var errors := _perform("sync_draft", {"base":draft})
	if not errors.is_empty(): _state = pristine
	return errors

func _apply_modules(base: Dictionary) -> PackedStringArray:
	var draft: Dictionary = _canonical(base)
	if not author_marks_valid(draft) or not context_sources_valid(draft.get("context_sources", [])): return PackedStringArray(["表达补丁来源或作者草稿无效。"])
	if draft.has("module_patch_record"):
		var old: Dictionary = draft.module_patch_record
		_strip_effects(draft, old.effects)
		for index in range(old.suffixes.size() - 1, -1, -1):
			var suffix: Dictionary = old.suffixes[index]
			var text := str(draft.slots.get(str(suffix.slot_id), ""))
			if text.ends_with(str(suffix.content)): draft.slots[str(suffix.slot_id)] = text.trim_suffix(str(suffix.content))
		draft.erase("module_patch_record")
	var kernel: Resource = null
	for entry in catalog.kernels:
		if str(entry.id) == str(draft.get("kernel_id", "")): kernel = entry
	if kernel == null or not draft.get("slots") is Dictionary: return PackedStringArray(["表达补丁不能替换原始基模。"])
	var record := {"record_index":_state.operations.size(), "effects":[], "suffixes":[], "modules":_state.module_slots.duplicate()}
	for module_slot in _state.module_slots.size():
		var module_id: String = str(_state.module_slots[module_slot])
		if str(module_id).is_empty(): continue
		var module: Dictionary = rules.find("modules", str(module_id))
		var amended := _effect_draft(draft, module.draft_effects)
		if amended.is_empty(): return PackedStringArray(["表达补丁字段无效。"])
		record.effects.append_array(_deltas(draft, amended, module.draft_effects))
		draft = amended
		var slot_id := str(kernel.required_slots[-1])
		var content := " · " + str(_state.module_contents[module_slot])
		draft.slots[slot_id] = str(draft.slots[slot_id]) + content
		record.suffixes.append({"slot_id":slot_id, "content":content})
	_state.module_records.append(record.duplicate(true))
	draft.module_patch_record = record
	_state.context_draft = draft
	_state.module_application = "补丁已经夹入你的表达。"
	return PackedStringArray()

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
	result.mass_balance = mass_balance()
	result.available_module_inventory = _available_inventory("module")
	result.available_solute_inventory = _available_inventory("solute")
	result.available_solvent_inventory = {}
	result.available_solvent_reserve = {}
	result.available_solvent_units = {}
	result.available_solvent_reserve_units = {}
	result.solvent_capacity_units = {}
	for solvent: Dictionary in rules.solvents:
		var id := str(solvent.id)
		var available := _available_count("solvent",id)
		var capacity := _solvent_capacity(id)
		result.available_solvent_units[id] = mini(available,capacity)
		result.available_solvent_reserve_units[id] = maxi(0,available-capacity)
		result.solvent_capacity_units[id] = capacity
		result.available_solvent_inventory[id] = float(mini(available,capacity))/_liquid_scale()
		result.available_solvent_reserve[id] = float(maxi(0,available-capacity))/_liquid_scale()
	if rules.definition_version >= 4:
		result.chamber_liquid_units = _state.chamber_solvents.duplicate()
		result.chamber_liquid_total_units = _chamber_liquid_total()
		result.chamber_liquid_capacity_units = rules.flask_liquid_capacity_units
		result.liquid_balance = liquid_balance()
		result.next_liquid_request_index = _state.liquid_requests.size()+1
		for id in result.solvent_inventory: result.solvent_inventory[id] = float(result.solvent_inventory[id])/_liquid_scale()
		for id in result.solvent_reserve: result.solvent_reserve[id] = float(result.solvent_reserve[id])/_liquid_scale()
		for id in result.chamber_solvents: result.chamber_solvents[id] = float(result.chamber_solvents[id])/_liquid_scale()
		for entry: Dictionary in result.last_distillation:
			entry.liquid_units = entry.amount
			entry.amount = float(entry.amount)/_liquid_scale()
		result.culture_volume = {"liquid_units":result.chamber_liquid_total_units,"pending_units":result.mass_balance.pending_units,"dissolved_units":result.mass_balance.dissolved_units,"solid_units":result.mass_balance.solid_units,"capacity_units":rules.flask_liquid_capacity_units}
		var module_units := 0
		for id in _state.module_slots:
			if not str(id).is_empty(): module_units += rules.module_volume_units
		var base_units: int = rules.neuron_base_volume_units if not str(_state.core_kernel_id).is_empty() else 0
		result.neuron_volume = {"base_units":base_units,"module_units":module_units,"applied_solid_units":result.mass_balance.applied_units,"total_units":base_units+module_units+int(result.mass_balance.applied_units)}
	if rules.definition_version >= 5: _snapshot_layers(result)
	result.explanation = "五层脑切片分别承载语言、群体、话题、立场与语用。" if rules.definition_version >= 5 else "培养数值与神经拓扑为游戏设计；沸腾顺序不是物理温度。外部版本只读，来源与控制权不变。"
	return result

func payload() -> Dictionary:
	return _state.duplicate(true)

func record_errors() -> PackedStringArray:
	return PackedStringArray(["设计操作记录已达有限上限。"] if _state.operations.size() >= RECORD_LIMIT else [])

func validate_payload(data: Dictionary, events: Array, variants: Array, economy: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	data = _canonical(data)
	if rules.definition_version >= 5 and data.get("design_version") in [1,2,3,4]:
		return SliceLegacyDesign.new(catalog, SLICE_LEGACY_RULES).validate_payload(data,events,variants,economy)
	if rules.definition_version >= 4 and data.get("design_version") in [1,2,3]:
		return get_script().new(catalog, QUARTER_RULES).validate_payload(data,events,variants,economy)
	if data.get("design_version") in [1,2]:
		return PreviousDesign.new(catalog, PREVIOUS_RULES).validate_payload(data,events,variants,economy)
	if not _integer(data.get("design_version")) or int(data.design_version) != (5 if rules.definition_version >= 5 else (4 if rules.definition_version >= 4 else 3)) or not data.get("rules_signature") is String or data.rules_signature != rules.signature() or not data.get("operations") is Array or data.operations.size() > RECORD_LIMIT:
		return PackedStringArray(["设计存档版本、定义或操作记录错误。"])
	var replay = get_script().new(catalog, rules)
	var published := {}
	for operation: Variant in data.operations:
		if not operation is Dictionary or not operation.get("action") is String or not operation.get("params") is Dictionary:
			errors.append("设计存档操作类型错误。")
			continue
		var source := {}
		var params: Dictionary = operation.params
		if operation.action in ["claim","request_material"]:
			for event: Dictionary in events:
				if str(event.get("instance_id", "")) == str(params.get("instance_id", "")): source = event
		elif operation.action == "publish":
			var id := str(params.get("variant_id", ""))
			if published.has(id): errors.append("设计存档重复发布模块奖励。")
			published[id] = true
			for variant: Dictionary in variants:
				if str(variant.get("id", "")) == id: source = variant
		elif operation.action == "choose_starter" and not published.is_empty(): errors.append("开局选择必须在首发之前。")
		elif operation.action == "legacy_import":
			if not replay._state.operations.is_empty(): errors.append("旧设计导入只能是首条操作。")
			source = {"events":events, "variants":variants, "economy":economy}
			if params.get("payload") is Dictionary and params.payload.get("operations") is Array:
				for old_id in _recorded_publishes(params.payload): published[old_id] = true
		errors.append_array(replay._perform(operation.action, params, source))
	for variant: Dictionary in variants:
		if variant.get("controlled", false) and variant.get("creator", "") == "player" and not published.has(str(variant.get("id", ""))): errors.append("设计存档缺少玩家版本模块来源。")
	if not errors.is_empty(): return errors
	for variant: Dictionary in variants:
		if not replay.context_sources_valid(variant.get("context_sources", [])): errors.append("版本固体来源不符合已应用记录。")
		if not replay.author_marks_valid(variant): errors.append("版本表达补丁或能力来源不符合操作记录。")
	if _canonical(replay.payload()) != data: errors.append("设计存档状态不符合操作记录，拒绝部分恢复。")
	var mass: Dictionary = replay.mass_balance()
	if int(mass.supplied_units) != int(mass.accounted_units): errors.append("培养材料数量不守恒。")
	if rules.definition_version >= 4:
		var liquid: Dictionary = replay.liquid_balance()
		if liquid.supplied_units != liquid.accounted_units: errors.append("溶剂数量不守恒。")
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

func restore(data: Dictionary, events: Array = [], variants: Array = [], economy: Dictionary = {}, base: Dictionary = {}) -> PackedStringArray:
	var errors := validate_payload(data, events, variants, economy)
	if not errors.is_empty(): return errors
	if _integer(data.get("design_version")) and int(data.design_version) in ([1,2,3,4] if rules.definition_version >= 5 else ([1,2,3] if rules.definition_version >= 4 else [1,2])):
		var ids: Array = []
		for variant: Dictionary in variants: ids.append(str(variant.id))
		var candidate: RefCounted = get_script().new(catalog, rules)
		errors = candidate._perform("legacy_import", {"payload":data, "variant_ids":ids,"base":base}, {"events":events, "variants":variants, "economy":economy})
		if errors.is_empty(): _state = candidate.payload()
		return errors
	_state = _canonical(data)
	return errors

func _import_legacy(params: Dictionary,source: Dictionary) -> PackedStringArray:
	if rules.definition_version >= 5: return _import_slice_state(params,source)
	if rules.definition_version >= 4: return _import_quarter_state(params,source)
	if not _state.operations.is_empty() or not params.get("payload") is Dictionary or not params.get("variant_ids") is Array or not source.has_all(["events","variants","economy"]): return PackedStringArray(["旧设计导入记录无效。"])
	var old: Dictionary = params.payload
	if old.get("design_version") not in [1,2]: return PackedStringArray(["旧设计版本未登记。"])
	var variants: Array = []
	var found := {}
	for variant: Dictionary in source.variants:
		if str(variant.id) in params.variant_ids:
			variants.append(variant)
			found[str(variant.id)] = true
	if found.size() != params.variant_ids.size(): return PackedStringArray(["旧设计的真实版本来源丢失。"])
	var economy: Dictionary = source.economy.duplicate(true)
	economy.transactions = economy.get("transactions",[]).filter(func(entry: Dictionary)->bool: return not str(entry.get("reason","")).begins_with("技能解锁：") or str(entry.reason).trim_prefix("技能解锁：") in old.get("unlocked_skills",[]))
	var reader: RefCounted = PreviousDesign.new(catalog,PREVIOUS_RULES)
	var errors: PackedStringArray = reader.restore(old,source.events,variants,economy)
	if not errors.is_empty(): return errors
	var previous: Dictionary = reader.payload()
	var fresh := _state.duplicate(true)
	_state = previous.duplicate(true)
	_state.design_version = 3
	_state.rules_signature = rules.signature()
	_state.operations = []
	for field in ["chamber_pending","chamber_dissolved","flask_solids","mass_serial","discarded_sources","legacy_discarded_units","event_material_claims","module_positions"]: _state[field] = fresh[field]
	var old_mortar: Dictionary = previous.mortar
	_state.mortar = _empty_mortar()
	if int(old_mortar.count) > 0:
		_state.mortar = {"solute_id":old_mortar.solute_id,"count":1,"state":"ground","progress":rules.grinding_distance,"reversals":rules.grinding_reversals,"direction":0,"quantity_units":rules.mass_units_per_solute,"source":_batch_source(old_mortar.source,rules.mass_units_per_solute)}
	for index in _state.bottles.size():
		var bottle: Dictionary = _state.bottles[index]
		if bottle.state == "empty":
			_state.bottles[index] = _empty_bottle(index)
			continue
		var provenance := _batch_source(bottle.source,rules.mass_units_per_solute)
		if bottle.state == "filled": _state.bottles[index] = _filled_bottle(index,str(bottle.solute_id),provenance)
		elif bottle.state == "solid":
			_state.mass_serial += 1
			_state.flask_solids.append({"id":"solid_%04d" % int(_state.mass_serial),"legacy_slot":index,"solute_id":bottle.solute_id,"context_id":bottle.context_id,"quantity_units":rules.mass_units_per_solute,"source":provenance})
			_state.bottles[index] = _empty_bottle(index)
		else:
			var via := {}
			if previous.stirred and not previous.chamber_solvents.is_empty(): via[str(previous.chamber_solvents.keys()[0])] = rules.mass_units_per_solute
			var portion := {"solute_id":bottle.solute_id,"quantity_units":rules.mass_units_per_solute,"source":provenance,"via":via}
			_append_portion(_state.chamber_dissolved if previous.stirred else _state.chamber_pending,portion)
			_state.bottles[index] = _empty_bottle(index)
	_state.chamber_slots = []
	# Previously automatic tabletop rewards stay claimed, never respawn on migration.
	for provenance: Dictionary in _state.inventory_sources: _state.event_material_claims.append(provenance.duplicate(true))
	var balance: Dictionary = mass_balance()
	_state.legacy_discarded_units = maxi(0,int(balance.supplied_units)-int(balance.accounted_units))
	return errors

func _recorded_publishes(data: Dictionary) -> Array:
	var ids: Array = []
	for operation: Variant in data.get("operations",[]):
		if not operation is Dictionary or not operation.get("params") is Dictionary: continue
		if operation.get("action") == "publish": ids.append(str(operation.params.get("variant_id","")))
		elif operation.get("action") == "legacy_import": ids.append_array(operation.params.get("variant_ids",[]))
	return ids

func legacy_draft_marks() -> Array:
	var result: Array = []
	for application: Dictionary in _state.skill_applications:
		if int(application.publish_index) == int(_state.current_publish_index) - 1 and application.has("effects"): result.append(application.duplicate(true))
	return result

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
	return {"slot":slot,"state":"empty","solute_id":"","solvent_id":"","context_id":"","quantity_units":0}

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func _canonical(value: Variant) -> Variant:
	# JSON numbers are floats; design quantities and indexes are integral.
	if value is float and _integer(value): return int(value)
	if value is Vector2: return _canonical([float(value.x),float(value.y)])
	if value is PackedStringArray: return _canonical(Array(value))
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

func _default_module_position(slot: int) -> Array:
	return [.18+.60*slot/maxf(rules.module_slots-1,1),.82]

func _empty_mortar() -> Dictionary:
	return {"solute_id":"","count":0,"state":"empty","progress":0.0,"reversals":0,"direction":0,"quantity_units":0,"source":{}}

func _batch_source(source: Dictionary,units: int) -> Dictionary:
	var result := source.duplicate(true)
	if not result.has("batch_id"):
		_state.mass_serial += 1
		result.batch_id = "mass_%04d" % int(_state.mass_serial)
	result.portion_units = units
	return result

func _filled_bottle(slot: int,id: String,source: Dictionary) -> Dictionary:
	var units := int(source.get("portion_units",rules.mass_units_per_solute))
	return {"slot":slot,"state":"filled","solute_id":id,"solvent_id":"","context_id":"","quantity_units":units,"source":_batch_source(source,units)}

func _append_portion(values: Array,portion: Dictionary) -> void:
	for current: Dictionary in values:
		if current.source.batch_id != portion.source.batch_id: continue
		current.quantity_units += int(portion.quantity_units)
		current.source.portion_units = int(current.quantity_units)
		for key in portion.via: current.via[key] = int(current.via.get(key,0))+int(portion.via[key])
		return
	values.append(portion.duplicate(true))

func _dissolve_pending() -> PackedStringArray:
	if _state.chamber_solvents.is_empty(): return PackedStringArray(["先倒入粉末与溶剂，再搅拌。"])
	if _state.chamber_pending.is_empty():
		if _state.chamber_dissolved.is_empty() or _state.stirred: return PackedStringArray(["没有待搅拌的材料。"])
		_state.stirred = true
		return PackedStringArray()
	var used := {}
	var used_solutes := {}
	for portion: Dictionary in _state.chamber_dissolved:
		for solvent in portion.via:
			used[solvent] = int(used.get(solvent,0))+int(portion.via[solvent])
			var key: String = str(solvent)+"/"+str(portion.solute_id)
			used_solutes[key] = int(used_solutes.get(key,0))+int(portion.via[solvent])
	var changed := 0
	for portion: Dictionary in _state.chamber_pending:
		var remaining := int(portion.quantity_units)
		var via := {}
		for solvent: Dictionary in rules.solvents:
			var solvent_id := str(solvent.id)
			var doses := int(_state.chamber_solvents.get(solvent_id,0))
			var key := solvent_id+"/"+str(portion.solute_id)
			var total_free := maxi(0,_liquid_capacity(doses,int(solvent.saturation_units))-int(used.get(solvent_id,0)))
			var compatible_free := maxi(0,_liquid_capacity(doses,int(rules.solubility_caps[solvent_id][str(portion.solute_id)]))-int(used_solutes.get(key,0)))
			var amount := mini(remaining,mini(total_free,compatible_free))
			if amount <= 0: continue
			via[solvent_id] = amount
			used[solvent_id] = int(used.get(solvent_id,0))+amount
			used_solutes[key] = int(used_solutes.get(key,0))+amount
			remaining -= amount
		var dissolved := int(portion.quantity_units)-remaining
		if dissolved > 0:
			var result := portion.duplicate(true)
			result.quantity_units = dissolved
			result.source.portion_units = dissolved
			result.via = via
			_append_portion(_state.chamber_dissolved,result)
			changed += dissolved
		portion.quantity_units = remaining
		portion.source.portion_units = remaining
	if changed == 0: return PackedStringArray(["溶液已饱和，或这些溶剂无法溶解当前材料。"])
	_state.chamber_pending = _state.chamber_pending.filter(func(portion: Dictionary)->bool: return int(portion.quantity_units)>0)
	_state.stirred = true
	return PackedStringArray()

func _solid_index(params: Dictionary,legacy_slot: int) -> int:
	for index in _state.flask_solids.size():
		var solid: Dictionary = _state.flask_solids[index]
		if params.has("solid_id") and str(solid.id) == str(params.solid_id): return index
		if not params.has("solid_id") and legacy_slot >= 0 and int(solid.get("legacy_slot",-1)) == legacy_slot: return index
	return -1

func _portion_effects(effects: Array,source: Dictionary) -> Array:
	var result := effects.duplicate(true)
	var fraction := float(source.get("portion_units",rules.mass_units_per_solute))/float(rules.mass_units_per_solute)
	for effect: Dictionary in result: effect.amount = float(effect.amount)*fraction
	return result

func request_event_material(event: Dictionary,kind: String,id: String) -> PackedStringArray:
	var pristine := _state.duplicate(true)
	var errors := _perform("request_material",{"instance_id":str(event.get("instance_id","")),"kind":kind,"id":id},event)
	if not errors.is_empty(): _state = pristine
	return errors

func _request_material(params: Dictionary,event: Dictionary) -> PackedStringArray:
	var instance_id := str(params.get("instance_id",""))
	var kind := str(params.get("kind",""))
	var id := str(params.get("id",""))
	if instance_id.is_empty() or str(event.get("instance_id","")) != instance_id or not event.get("design_rewards") is Array: return PackedStringArray(["物资纸片必须来自本局真实事件。"])
	for current: Dictionary in _state.event_material_claims:
		if current.source_instance_id == instance_id and current.kind == kind and current.id == id: return PackedStringArray(["这张物资纸片已经搬出。"])
	var count := 0
	for reward: Variant in event.design_rewards:
		if not reward is Dictionary or not reward.get("kind") is String or not reward.get("id") is String or not _integer(reward.get("count")) or int(reward.count)<=0: return PackedStringArray(["事件物资来源记录无效。"])
		if str(reward.kind) == kind and str(reward.id) == id: count += int(reward.count)
	if count <= 0: return PackedStringArray(["事件没有这份物资。"])
	_state.event_material_claims.append({"source_instance_id":instance_id,"definition_id":str(event.get("definition_id","")),"preset_id":str(event.get("design_source_preset_id","")),"kind":kind,"id":id,"count":count})
	return PackedStringArray()

func _material_requested(instance_id: String,kind: String,id: String) -> bool:
	if instance_id == "initial": return true
	for claim: Dictionary in _state.event_material_claims:
		if claim.source_instance_id == instance_id and claim.kind == kind and claim.id == id: return true
	return false

func _private_count(kind: String,id: String) -> int:
	var count := 0
	for source: Dictionary in _state.inventory_sources:
		if source.kind == kind and source.id == id and not _material_requested(str(source.source_instance_id),kind,id): count += int(source.count)
	return count

func _available_count(kind: String,id: String) -> int:
	var key: String = {"module":"module_inventory","solute":"solute_inventory","solvent":"solvent_inventory"}.get(kind,"")
	if key.is_empty(): return 0
	var owned := int(_state[key].get(id,0))
	if kind == "solvent": owned += int(_state.solvent_reserve.get(id,0))
	return maxi(0,owned-_private_count(kind,id)*(_liquid_scale() if kind == "solvent" else 1))

func _available_inventory(kind: String) -> Dictionary:
	var result := {}
	var key: String = {"module":"module_inventory","solute":"solute_inventory"}[kind]
	for id in _state[key]: result[id] = _available_count(kind,str(id))
	return result

func _available_source_index(sources: Array,kind: String,id: String) -> int:
	for index in sources.size():
		if _material_requested(str(sources[index].get("source_instance_id","initial")),kind,id): return index
	return -1

func mass_balance() -> Dictionary:
	var supplied: int = rules.initial_solute_count*rules.solutes.size()*rules.mass_units_per_solute
	for source: Dictionary in _state.inventory_sources:
		if source.kind == "solute": supplied += int(source.count)*rules.mass_units_per_solute
	var raw := 0
	var ground := 0
	for value in _state.solute_inventory.values(): raw += int(value)*rules.mass_units_per_solute
	for value in _state.ground_inventory.values(): ground += int(value)*rules.mass_units_per_solute
	var bottles := 0
	for bottle: Dictionary in _state.bottles: bottles += int(bottle.get("quantity_units",0))
	var pending := 0
	var dissolved := 0
	var solid := 0
	for portion: Dictionary in _state.chamber_pending: pending += int(portion.quantity_units)
	for portion: Dictionary in _state.chamber_dissolved: dissolved += int(portion.quantity_units)
	for portion: Dictionary in _state.flask_solids: solid += int(portion.quantity_units)
	var stored := 0
	for sources: Array in _state.context_sources.values():
		for source: Dictionary in sources: stored += int(source.get("portion_units",rules.mass_units_per_solute))
	var applied := 0
	for source: Dictionary in _state.applied_context_sources: applied += int(source.get("portion_units",rules.mass_units_per_solute))
	var discarded := int(_state.legacy_discarded_units)
	for source: Dictionary in _state.discarded_sources: discarded += int(source.get("portion_units",rules.mass_units_per_solute))
	var mortar := int(_state.mortar.get("quantity_units",0))
	return {"supplied_units":supplied,"raw_units":raw,"ground_units":ground,"mortar_units":mortar,"bottle_units":bottles,"pending_units":pending,"dissolved_units":dissolved,"solid_units":solid,"stored_units":stored,"applied_units":applied,"discarded_units":discarded,"accounted_units":raw+ground+mortar+bottles+pending+dissolved+solid+stored+applied+discarded}

func _liquid_scale() -> int:
	return rules.liquid_units_per_quarter if rules.definition_version >= 4 else 1

func _solvent_capacity(id: String) -> int:
	return int(rules.find("solvents",id).get("capacity",0))*_liquid_scale()

func _chamber_liquid_total() -> int:
	var total := 0
	for units in _state.chamber_solvents.values(): total += int(units)
	return total

@warning_ignore("integer_division")
func _liquid_capacity(units: int, capacity: int) -> int:
	return units*capacity/_liquid_scale()

func liquid_balance() -> Dictionary:
	var total := {"supplied_units":0,"stock_units":0,"reserve_units":0,"chamber_units":0,"evaporated_units":0,"accounted_units":0,"by_solvent":{}}
	for solvent: Dictionary in rules.solvents:
		var id := str(solvent.id)
		var supplied := int(solvent.get("initial_count",rules.initial_solvent_count))*_liquid_scale()
		for source: Dictionary in _state.inventory_sources:
			if source.kind == "solvent" and source.id == id: supplied += int(source.count)*_liquid_scale()
		var row := {"supplied_units":supplied,"stock_units":int(_state.solvent_inventory[id]),"reserve_units":int(_state.solvent_reserve[id]),"chamber_units":int(_state.chamber_solvents.get(id,0)),"evaporated_units":int(_state.get("evaporated_solvents",{}).get(id,0))}
		row.accounted_units = row.stock_units+row.reserve_units+row.chamber_units+row.evaporated_units
		total.by_solvent[id] = row
		for key in row: total[key] += int(row[key])
	return total

func _import_quarter_state(params: Dictionary, source: Dictionary) -> PackedStringArray:
	if not _state.operations.is_empty() or not params.get("payload") is Dictionary or not params.get("variant_ids") is Array or not source.has_all(["events","variants","economy"]): return PackedStringArray(["旧设计导入记录无效。"])
	var old: Dictionary = params.payload
	if old.get("design_version") not in [1,2,3]: return PackedStringArray(["旧设计版本未登记。"])
	var variants: Array = []
	var found := {}
	for variant: Dictionary in source.variants:
		if str(variant.id) in params.variant_ids:
			variants.append(variant)
			found[str(variant.id)] = true
	if found.size() != params.variant_ids.size(): return PackedStringArray(["旧设计的真实版本来源丢失。"])
	var economy: Dictionary = source.economy.duplicate(true)
	economy.transactions = economy.get("transactions",[]).filter(func(entry: Dictionary)->bool: return not str(entry.get("reason","")).begins_with("技能解锁：") or str(entry.reason).trim_prefix("技能解锁：") in old.get("unlocked_skills",[]))
	var reader: RefCounted = get_script().new(catalog, QUARTER_RULES)
	var errors: PackedStringArray = reader.restore(old,source.events,variants,economy)
	if not errors.is_empty(): return errors
	_state = reader.payload()
	_state.design_version = 4
	_state.rules_signature = rules.signature()
	_state.operations = []
	_state.liquid_requests = []
	_state.evaporated_solvents = {}
	for field in ["solvent_inventory","solvent_reserve","chamber_solvents"]:
		for id in _state[field]: _state[field][id] = int(_state[field][id])*_liquid_scale()
	for entry: Dictionary in _state.last_distillation: entry.amount = int(entry.amount)*_liquid_scale()
	var balance := liquid_balance()
	for id in balance.by_solvent:
		var row: Dictionary = balance.by_solvent[id]
		_state.evaporated_solvents[id] = int(row.supplied_units)-int(row.stock_units)-int(row.reserve_units)-int(row.chamber_units)
	return errors
