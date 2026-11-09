class_name MemeDemoDesignState
extends RefCounted

const DEFAULT_RULES = preload("res://data/rules/design_rules.tres")
const Composition = preload("res://scripts/gameplay/design/meme_composition.gd")
const DESIGN_VERSION := 9
const RECORD_LIMIT := 65536
var catalog: MemeDemoCatalog
var rules: MemeDesignRules
var _state: Dictionary = {}
var _layer_repeat := false

func _reset_layers() -> void:
	_state.context_resource_inventory = {}
	_state.context_initial_inventory = {}
	_state.context_layers = {}
	_state.layer_records = []
	_state.axis_requests = []
	_state.layers_initialized = false
	for entry: Dictionary in rules.context_definitions.entries:
		_state.context_resource_inventory[str(entry.id)] = int(entry.initial_count)
		_state.context_initial_inventory[str(entry.id)] = int(entry.initial_count)
	for index in 5:
		var layer: String = ["language", "group", "topics", "stance", "pragmatic"][index]
		if index < 3:
			var slots: Array = []
			var origins: Array = []
			for slot in 3:
				slots.append({})
				origins.append("")
			_state.context_layers[layer] = {"slots":slots,"origins":origins,"depth":float(rules.context_depths[index])}
		else:
			_state.context_layers[layer] = {"origin":[0.0,0.0],"current":[0.0,0.0],"offsets":[0,0],"known":false,"depth":float(rules.context_depths[index])}
		_state.context_layers[layer].attached = true
		_state.context_layers[layer].plane_id = "context-plane:%s:%s" % [str(_state.starter_preset_id) if not str(_state.starter_preset_id).is_empty() else "unselected",layer]
func _preset_context_base(id: String) -> Dictionary:
	var preset: Resource = catalog.find_preset(id)
	var base: Dictionary = rules.starter_contexts.get(id,{}).duplicate(true)
	for field in ["political_position","pragmatic_position"]:
		var point: Variant = base.get(field)
		if point is Array and point.size() == 2: base[field] = Vector2(float(point[0]),float(point[1]))
	return _canonical(preset.to_draft(base))

func _context_id(kind: String, value: String) -> String:
	for entry: Dictionary in rules.context_definitions.entries:
		if str(entry.kind) == kind and str(entry.value) == value: return str(entry.id)
	return ""

func _initialize_layers(base: Dictionary) -> PackedStringArray:
	base = _canonical(base)
	for pair in [["language","language_id"],["group","group_id"]]:
		var id := _context_id(pair[0],str(base.get(pair[1],"")))
		if id.is_empty() or _context_available(id)-_installed_context(id) <= 0: return PackedStringArray([DeskLocalization.source("LOC_PRESET_LACKS_AN_AVAILABLE_LANGUAGE_OR_AUDIENCE_267B3DA7")])
		_state.context_layers[pair[0]].slots[0] = {"resource_id":id,"source":_context_unit_source(id)}
		_state.context_layers[pair[0]].origins[0] = id
	var topics: Variant = base.get("topic_ids",[])
	if not topics is Array or topics.size() > 3: return PackedStringArray([DeskLocalization.source("LOC_PRESET_TOPICS_EXCEED_THE_THREE_AVAILABLE_SLOTS_15C33F06")])
	for index in topics.size():
		var id := _context_id("topic",str(topics[index]))
		if id.is_empty() or _installed_context(id) > 0 or _context_available(id) <= 0: return PackedStringArray([DeskLocalization.source("LOC_PRESET_TOPICS_ARE_INVALID_DUPLICATED_OR_EXCEED_08EF7D31")])
		_state.context_layers.topics.slots[index] = {"resource_id":id,"source":_context_unit_source(id)}
		_state.context_layers.topics.origins[index] = id
	for pair in [["stance","political_position"],["pragmatic","pragmatic_position"]]:
		var point: Variant = base.get(pair[1],[0.0,0.0])
		if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]) or absf(float(point[0])) > 1 or absf(float(point[1])) > 1: return PackedStringArray([DeskLocalization.source("LOC_INVALID_PRESET_D_CONTEXT_COORDINATES_A40AD586")])
		_state.context_layers[pair[0]].origin = point.duplicate()
		_state.context_layers[pair[0]].current = point.duplicate()
		_state.context_layers[pair[0]].known = bool(base.get("political_known",false)) if pair[0] == "stance" else true
	for layer: String in _state.context_layers:
		_state.context_layers[layer].plane_id = "context-plane:%s:%s" % [str(_state.starter_preset_id) if not str(_state.starter_preset_id).is_empty() else "imported",layer]
	_state.layers_initialized = true
	return _apply_layers(base)

func _installed_context(id: String) -> int:
	var count := 0
	for layer in ["language","group","topics"]:
		for slot: Dictionary in _state.context_layers[layer].slots:
			if str(slot.get("resource_id","")) == id: count += 1
	return count

func context_slot_capacity(layer: String, _installed_modules: Variant = null) -> int:
	return 3 if layer in ["language","group","topics"] else 0

func _context_capacity_errors(modules: Array) -> PackedStringArray:
	for layer in ["language","group"]:
		var slots: Array = _state.context_layers.get(layer,{}).get("slots",[])
		for index in range(context_slot_capacity(layer,modules),slots.size()):
			if not slots[index].is_empty(): return PackedStringArray([DeskLocalization.source("LOC_REMOVE_RESOURCES_FROM_THE_EXPANDED_CONTEXT_SLOTS_C6DD12ED")])
	return PackedStringArray()

func _valid_context_slot(layer: String, slot: Dictionary) -> bool:
	var id := str(slot.get("resource_id",""))
	var entry: Dictionary = rules.context_resource(id)
	var source: Variant = slot.get("source")
	if str(entry.get("kind","")) != layer or not source is Dictionary: return false
	for provenance: Dictionary in _context_sources(id):
		var unit: Dictionary = source.duplicate(true)
		unit.erase("unit_id")
		if _canonical(unit) != _canonical(provenance): continue
		for index in int(provenance.count):
			if str(source.get("unit_id","")) == "%s:%s:%s:%d" % [provenance.source_instance_id,provenance.kind,id,index]: return true
	return false

func required_context_errors() -> PackedStringArray:
	if not _state.layers_initialized: return PackedStringArray([DeskLocalization.source("LOC_CONFIRM_A_STARTING_MEME_AND_INSTALL_LANGUAGE_352C120F")])
	var errors := PackedStringArray()
	for layer in ["language","group"]:
		var data: Dictionary = _state.context_layers.get(layer,{})
		var valid := false
		var slots: Array = data.get("slots",[])
		if bool(data.get("attached",true)):
			for index in mini(context_slot_capacity(layer),slots.size()):
				valid = valid or _valid_context_slot(layer,slots[index])
		if not valid: errors.append(DeskLocalization.source_format("LOC_INSTALL_AT_LEAST_ONE_VALID_S_SLOT_2A8F7FA2", (DeskLocalization.source("LOC_LANGUAGE_9F6FEE1A") if layer == "language" else DeskLocalization.source("LOC_AUDIENCE_D14FC4B5")), [0]))
	return errors

func _context_available(id: String) -> int:
	var entry: Dictionary = rules.context_resource(id)
	return maxi(0,int(_state.context_resource_inventory.get(id,0))-_private_count(str(entry.get("kind","")),id))

func _context_sources(id: String) -> Array:
	var entry: Dictionary = rules.context_resource(id)
	var count: int = int(_state.get("context_initial_inventory",{}).get(id,entry.get("initial_count",0)))
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
	if not _state.layers_initialized or not _state.context_layers.has(layer): return PackedStringArray([DeskLocalization.source("LOC_CONFIRM_A_STARTING_MEME_FIRST_11EAF3C4")])
	if action == "set_context_depth":
		if not _number(params.get("depth")) or float(params.depth) < 0 or float(params.depth) > 1: return PackedStringArray([DeskLocalization.source("LOC_SLICE_DEPTH_MUST_BE_IN_THE_RANGE_6D1A19C1")])
		_state.context_layers[layer].depth = float(params.depth)
		return PackedStringArray()
	if not params.get("base") is Dictionary: return PackedStringArray([DeskLocalization.source("LOC_CONTEXT_CONFIGURATION_REQUIRES_YOUR_OWN_DRAFT_AWAITING_084C0398")])
	if action in ["detach_context_layer","attach_context_layer"]:
		var data: Dictionary = _state.context_layers[layer]
		var target := action == "attach_context_layer"
		if bool(data.get("attached",true)) == target: return PackedStringArray([DeskLocalization.source("LOC_THE_SLICE_IS_ALREADY_IN_ITS_MATCHING_8BB39140")] )
		if params.has("plane_id") and str(params.plane_id) != str(data.plane_id): return PackedStringArray([DeskLocalization.source("LOC_SLICE_SOURCE_MISMATCH_7FA89B1D")] )
		data.attached = target
		return _apply_layers(params.base)
	if not bool(_state.context_layers[layer].attached): return PackedStringArray([DeskLocalization.source("LOC_RETURN_THIS_SLICE_TO_THE_BRAIN_FIRST_4F3C38DA")] )
	if action in ["install_context","remove_context"]:
		if layer not in ["language","group","topics"] or not _integer(params.get("slot")) or int(params.slot) < 0 or int(params.slot) >= context_slot_capacity(layer): return PackedStringArray([DeskLocalization.source("LOC_INVALID_CONTEXT_SLOT_17C28A5F")])
		var slot := int(params.slot)
		while _state.context_layers[layer].slots.size() <= slot:
			_state.context_layers[layer].slots.append({})
			_state.context_layers[layer].origins.append("")
		if action == "remove_context":
			if _state.context_layers[layer].slots[slot].is_empty(): return PackedStringArray([DeskLocalization.source("LOC_THIS_CONTEXT_SLOT_IS_EMPTY_F2C503FA")])
			_state.context_layers[layer].slots[slot] = {}
		else:
			var id := str(params.get("resource_id",""))
			var entry: Dictionary = rules.context_resource(id)
			if not _state.context_layers[layer].slots[slot].is_empty(): return PackedStringArray([DeskLocalization.source("LOC_REMOVE_THE_EXISTING_CONTEXT_RESOURCE_FIRST_72FBAD89")])
			if str(entry.get("kind","")) != ("topic" if layer == "topics" else layer) or _context_available(id)-_installed_context(id) <= 0: return PackedStringArray([DeskLocalization.source("LOC_NO_AVAILABLE_MATCHING_CONTEXT_RESOURCE_32BB7FCF")])
			if layer == "topics" and _installed_context(id) > 0: return PackedStringArray([DeskLocalization.source("LOC_THE_SAME_TOPIC_CANNOT_OCCUPY_MULTIPLE_SLOTS_E0AEF5DC")])
			var source := _context_unit_source(id)
			if source.is_empty(): return PackedStringArray([DeskLocalization.source("LOC_CONTEXT_RESOURCE_SOURCE_IS_UNAVAILABLE_A94CDFAF")])
			_state.context_layers[layer].slots[slot] = {"resource_id":id,"source":source}
	else:
		if layer not in ["stance","pragmatic"] or str(params.get("axis","")) not in ["x","y"] or not _integer(params.get("direction")) or int(params.direction) not in [-1,1]: return PackedStringArray([DeskLocalization.source("LOC_A_D_MOVE_ACCEPTS_ONE_STEP_ON_11740594")])
		if not params.get("request_id") is String or params.request_id.is_empty() or params.request_id.length() > 128: return PackedStringArray([DeskLocalization.source("LOC_A_D_MOVE_REQUIRES_A_BOUNDED_REQUEST_83645A17")])
		var request := {"request_id":str(params.request_id),"layer":layer,"axis":str(params.axis),"direction":int(params.direction)}
		for previous: Dictionary in _state.axis_requests:
			if previous.request_id == request.request_id:
				_layer_repeat = true
				return PackedStringArray() if previous == request else PackedStringArray([DeskLocalization.source("LOC_THIS_REQUEST_ID_HAS_ALREADY_BEEN_USED_C071C23E")])
		var axis := 0 if str(params.axis) == "x" else 1
		var data: Dictionary = _state.context_layers[layer]
		var old := int(data.offsets[axis])
		var next := old+int(params.direction)
		var origin := float(data.origin[axis])
		var minimum := int(floor((-1.0-origin)/rules.axis_step+0.000001))
		var maximum := int(ceil((1.0-origin)/rules.axis_step-0.000001))
		if next < minimum or next > maximum: return PackedStringArray([DeskLocalization.source("LOC_THE_COORDINATE_HAS_REACHED_ITS_BOUNDARY_2B0D9566")])
		var cost := absi(next)-absi(old)
		var token_id := _axis_token(layer,str(params.axis),1 if next > 0 else -1)
		if cost > 0 and _context_available(token_id)-_locked_token(token_id) < cost: return PackedStringArray([DeskLocalization.source("LOC_NOT_ENOUGH_TOKENS_FOR_THE_MATCHING_DIRECTION_A220DB22")])
		data.offsets[axis] = next
		data.current[axis] = float(Vector2(clampf(origin+float(next)*rules.axis_step,-1.0,1.0),0.0).x)
		data.known = true
		_state.axis_requests.append(request)
	return _apply_layers(params.base)

func _layer_fields() -> Dictionary:
	var result := {"language_id":"","group_id":"","topic_ids":[],"political_position":_state.context_layers.stance.current.duplicate(),"pragmatic_position":_state.context_layers.pragmatic.current.duplicate(),"political_known":_state.context_layers.stance.known}
	for pair in [["language","language_id"],["group","group_id"],["topics","topic_ids"]]:
		var values: Array = []
		for slot: Dictionary in _state.context_layers[pair[0]].slots:
			if slot.is_empty(): continue
			var value: String = str(rules.context_resource(str(slot.resource_id)).value)
			if value not in values: values.append(value)
		if pair[0] == "topics": result.topic_ids = values
		else:
			result[pair[1]] = values[0] if not values.is_empty() else ""
			# 多资源槽位额外记录列表，单资源槽位使用对应的主身份字段。
			if values.size() > 1: result[pair[0]+"_ids"] = values
	result.context_layer_attachment = {}
	for layer: String in _state.context_layers: result.context_layer_attachment[layer] = bool(_state.context_layers[layer].attached)
	return result

func _apply_layers(base: Dictionary) -> PackedStringArray:
	var draft: Dictionary = _canonical(base)
	if not author_marks_valid(draft): return PackedStringArray([DeskLocalization.source("LOC_INVALID_DRAFT_SOURCE_RECORD_2123E441")])
	var fields := _layer_fields()
	for key in ["language_ids","group_ids"]: draft.erase(key)
	draft.merge(fields,true)
	var errors := _composition_errors(draft)
	if not errors.is_empty(): return errors
	var record := {"index":_state.layer_records.size(),"fields":fields.duplicate(true)}
	_state.layer_records.append(record)
	draft.context_layer_record = record.duplicate(true)
	_state.context_draft = draft
	return PackedStringArray()

func layer_errors(base: Dictionary) -> PackedStringArray:
	if not _state.layers_initialized: return PackedStringArray()
	base = _canonical(base)
	var fields: Dictionary = _canonical(_layer_fields())
	for key in fields:
		if base.get(key) != fields[key]: return PackedStringArray([DeskLocalization.source("LOC_DRAFT_CONTEXT_CONFLICTS_WITH_BRAIN_SLICE_CONFIGURATION_CBA3F275")])
	for key in ["language_ids","group_ids"]:
		if base.has(key) and not fields.has(key): return PackedStringArray([DeskLocalization.source("LOC_DRAFT_CONTAINS_AN_UNINSTALLED_EXPANDED_CONTEXT_52E5354E")])
	return _composition_errors(base)

func _composition_errors(draft: Dictionary) -> PackedStringArray:
	var preset_id := str(draft.get("preset_id",""))
	var errors := rules.patch_errors(preset_id,_state.module_slots)
	if Composition.supports(preset_id): errors.append_array(Composition.validate(draft,_state.module_slots))
	return errors

func _snapshot_layers(result: Dictionary) -> void:
	result.next_axis_request_index = _state.axis_requests.size()+1
	result.context_layers = _state.context_layers.duplicate(true)
	for layer in ["language","group"]:
		var data: Dictionary = result.context_layers[layer]
		var capacity := context_slot_capacity(layer)
		data.slot_capacity = capacity
		data.slots.resize(capacity)
		for index in capacity:
			if not data.slots[index] is Dictionary: data.slots[index] = {}
		data.origins.resize(capacity)
		for index in capacity:
			if not data.origins[index] is String: data.origins[index] = ""
	result.required_context_errors = required_context_errors()
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
		result.context_layers[layer].axis_labels = {"x_negative":DeskLocalization.source("LOC_FREEDOM_D1047EED"),"x_positive":DeskLocalization.source("LOC_AUTHORITY_E9D827BA"),"y_negative":DeskLocalization.source("LOC_EQUALITY_14DD2491"),"y_positive":DeskLocalization.source("LOC_HIERARCHY_33771717")} if layer == "stance" else {"x_negative":DeskLocalization.source("LOC_SINCERITY_8BB7FF57"),"x_positive":DeskLocalization.source("LOC_IRONY_06D9BA32"),"y_negative":DeskLocalization.source("LOC_SUPPORT_D93373F8"),"y_positive":DeskLocalization.source("LOC_OPPOSITION_454F03C9")}

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

func _init(content: MemeDemoCatalog = null, definitions: MemeDesignRules = null) -> void:
	catalog = content
	rules = definitions if definitions != null else DEFAULT_RULES
	reset()

## 新局只建立模块、语境资源和可重放的作者操作账本。
func reset() -> void:
	_state = {"design_version":DESIGN_VERSION, "rules_signature":rules.signature(), "starter_preset_id":"",
		"core_kernel_id":"", "core_preset_id":"", "module_inventory":{}, "module_slots":[],
		"module_contents":[], "module_positions":[], "connections":[], "inventory_sources":[],
		"context_draft":{}, "current_publish_index":0, "skill_applications":[], "skill_application":"",
		"module_records":[], "module_application":"", "event_material_claims":[],
		"unlocked_skills":["text"], "claimed_events":[], "inventory_log":[], "operations":[]}
	for index in rules.module_slots:
		_state.module_slots.append("")
		_state.module_contents.append("")
		_state.module_positions.append(_default_module_position(index))
	_reset_layers()

func starter_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if catalog == null: return options
	for id in rules.starter_presets:
		var preset: Resource = catalog.find_preset(id)
		if preset == null: continue
		var draft: Dictionary = preset.to_draft({})
		options.append({"id":id, "title":preset.title, "kernel_id":str(preset.kernel_id), "slots":draft.slots,
			"family_anchor":preset.family_anchor, "context_hint":preset.context_hint, "source_presets":[preset.source_record()],
			"default_context":_preset_context_base(id)})
	return options

## 用户动作失败时恢复整个设计状态；成功动作才进入重放账本。
func perform(action: String, params: Dictionary = {}) -> PackedStringArray:
	if action in ["claim", "publish", "unlock", "sync_draft", "request_material"]: return PackedStringArray([DeskLocalization.source("LOC_ONLY_THE_SIMULATION_LEDGER_MAY_SUBMIT_THIS_D4C608B2")])
	var pristine := _state.duplicate(true)
	var errors := _perform(action, params)
	if not errors.is_empty(): _state = pristine
	return errors

func _perform(action: String, params: Dictionary, source: Dictionary = {}) -> PackedStringArray:
	params = _canonical(params)
	var errors := PackedStringArray()
	if _state.operations.size() >= RECORD_LIMIT: return PackedStringArray([DeskLocalization.source("LOC_DESIGN_ACTION_RECORD_HAS_REACHED_ITS_FINITE_37CDC932")])
	var slot := -1
	if action in ["install_module", "remove_module", "edit_module_content", "move_module"]:
		if not _integer(params.get("slot")) or int(params.slot) < 0 or int(params.slot) >= rules.module_slots:
			return PackedStringArray([DeskLocalization.source("LOC_SLOT_IS_OUTSIDE_ITS_FINITE_RANGE_F48EA765")])
		slot = int(params.slot)
	if action in ["install_context", "remove_context", "move_context_axis", "set_context_depth", "detach_context_layer", "attach_context_layer"]:
		errors = _perform_layer(action, params)
		if errors.is_empty() and not _layer_repeat:
			_state.operations.append({"action":action,"params":params.duplicate(true)})
		return errors
	match action:
		"choose_starter":
			var preset_id := str(params.get("preset_id", ""))
			if preset_id not in rules.starter_presets or catalog == null or catalog.find_preset(preset_id) == null:
				return PackedStringArray([DeskLocalization.source("LOC_UNREGISTERED_STARTING_PRESET_4CB00AC5")])
			if not str(_state.starter_preset_id).is_empty():
				return errors if _state.starter_preset_id == preset_id else PackedStringArray([DeskLocalization.source("LOC_THIS_RUN_S_STARTING_PRESET_HAS_BEEN_975050D9")])
			_state.starter_preset_id = preset_id
			_state.core_preset_id = preset_id
			_state.core_kernel_id = str(catalog.find_preset(preset_id).kernel_id)
			_grant_starter_module(preset_id)
			var expected: Dictionary = _preset_context_base(preset_id)
			var base: Variant = params.get("base", expected)
			if not base is Dictionary: return PackedStringArray([DeskLocalization.source("LOC_THE_STARTING_DRAFT_MUST_BE_AN_OBJECT_93CDB3F4")])
			for key in expected:
				if _canonical(base.get(key)) != _canonical(expected[key]): return PackedStringArray([DeskLocalization.source("LOC_STARTING_CONTEXT_ORIGIN_MUST_COME_FROM_A_84C13427")] )
			_grant_starter_context(base)
			errors = _initialize_layers(base)
			if not errors.is_empty(): return errors
		"install_module":
			var module_id := str(params.get("module_id", ""))
			if rules.find("modules", module_id).is_empty() or _available_module_count(module_id) <= 0:
				return PackedStringArray([DeskLocalization.source("LOC_THIS_MODULE_IS_NOT_IN_STORAGE_7C77E7E3")])
			var used := 0
			for index in _state.module_slots.size():
				if index != slot and _state.module_slots[index] == module_id: used += 1
			if used >= _available_module_count(module_id): return PackedStringArray([DeskLocalization.source("LOC_NOT_ENOUGH_MODULES_HAVE_BEEN_TAKEN_OUT_F84E3A66")])
			if not params.get("base") is Dictionary: return PackedStringArray([DeskLocalization.source("LOC_AN_EXPRESSION_PATCH_REQUIRES_YOUR_OWN_DRAFT_984A1272")])
			if not rules.module_compatible(str(params.base.get("preset_id","")), module_id): return PackedStringArray([DeskLocalization.source("LOC_PATCH_INCOMPATIBLE_MEME")])
			var content: Variant = params.get("content", rules.find("modules", module_id).content)
			if not content is String or content.strip_edges().is_empty() or content.length() > 2048: return PackedStringArray([DeskLocalization.source("LOC_PATCH_CONTENT_MUST_BE_BOUNDED_NON_EMPTY_F87EF1F2")])
			var next_modules: Array = _state.module_slots.duplicate()
			next_modules[slot] = module_id
			errors = rules.patch_errors(str(params.base.get("preset_id","")),next_modules)
			if not errors.is_empty(): return errors
			errors = _context_capacity_errors(next_modules)
			if not errors.is_empty(): return errors
			_state.module_slots[slot] = module_id
			_state.module_contents[slot] = content
			errors = _apply_modules(params.base)
			if not errors.is_empty(): return errors
		"remove_module":
			if str(_state.module_slots[slot]).is_empty(): return PackedStringArray([DeskLocalization.source("LOC_THIS_SLOT_HAS_NO_EXPRESSION_PATCH_90260171")])
			if not params.get("base") is Dictionary: return PackedStringArray([DeskLocalization.source("LOC_REMOVING_A_PATCH_REQUIRES_YOUR_OWN_DRAFT_C0DFA4F7")])
			var next_modules: Array = _state.module_slots.duplicate()
			next_modules[slot] = ""
			errors = rules.patch_errors(str(params.base.get("preset_id","")),next_modules)
			if not errors.is_empty(): return errors
			errors = _context_capacity_errors(next_modules)
			if not errors.is_empty(): return errors
			_state.module_slots[slot] = ""
			_state.module_contents[slot] = ""
			_state.module_positions[slot] = _default_module_position(slot)
			_state.connections = _state.connections.filter(func(edge: Dictionary) -> bool: return int(edge.from) != slot and int(edge.to) != slot)
			errors = _apply_modules(params.base)
			if not errors.is_empty(): return errors
		"edit_module_content":
			var content: Variant = params.get("content")
			if str(_state.module_slots[slot]).is_empty() or not params.get("base") is Dictionary or not content is String or content.strip_edges().is_empty() or content.length() > 2048: return PackedStringArray([DeskLocalization.source("LOC_REQUIRES_AN_INSTALLED_PATCH_YOUR_OWN_DRAFT_CAC2A0FE")])
			_state.module_contents[slot] = content
			errors = _apply_modules(params.base)
			if not errors.is_empty(): return errors
		"move_module":
			var point: Variant = params.get("position")
			if str(_state.module_slots[slot]).is_empty() or not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]) or float(point[0]) < 0 or float(point[0]) > 1 or float(point[1]) < 0 or float(point[1]) > 1: return PackedStringArray([DeskLocalization.source("LOC_ONLY_INSTALLED_PATCH_NEURONS_WITHIN_THE_PAPER_F0E00E36")])
			_state.module_positions[slot] = point.duplicate()
		"connect":
			if not _integer(params.get("from")) or not _integer(params.get("to")):
				return PackedStringArray([DeskLocalization.source("LOC_WRONG_CONNECTION_SLOT_TYPE_7FF11DFF")])
			var first := int(params.from)
			var second := int(params.to)
			if first < 0 or second < 0 or first >= rules.module_slots or second >= rules.module_slots or first == second or str(_state.module_slots[first]).is_empty() or str(_state.module_slots[second]).is_empty():
				return PackedStringArray([DeskLocalization.source("LOC_A_CONNECTION_REQUIRES_TWO_DISTINCT_PLACED_MODULE_E271A8B2")])
			var connection := {"from":first, "to":second}
			if connection in _state.connections: return PackedStringArray([DeskLocalization.source("LOC_THIS_CONNECTION_ALREADY_EXISTS_1BFCDA18")])
			_state.connections.append(connection)
		"apply_skill":
			var skill_id := str(params.get("skill_id", ""))
			var skill: Dictionary = rules.find("skills", skill_id)
			if skill_id not in _state.unlocked_skills or skill.get("draft_effects", []).is_empty(): return PackedStringArray([DeskLocalization.source("LOC_THIS_ABILITY_IS_LOCKED_OR_HAS_NO_553BFB9A")])
			if not params.get("base") is Dictionary: return PackedStringArray([DeskLocalization.source("LOC_APPLYING_AN_ABILITY_REQUIRES_A_VALID_AUTHOR_7C886A86")])
			var draft := revision_base(params.base)
			if draft.is_empty(): return PackedStringArray([DeskLocalization.source("LOC_INVALID_AUTHOR_DRAFT_FIELDS_OR_SOLID_PROVENANCE_9B401655")])
			_state.context_draft = draft
			_state.skill_application = DeskLocalization.source_format("LOC_S_IS_HELPING_YOUR_EXPRESSION_TRAVEL_FURTHER_21DB569F", str(skill.title), [0])
		"request_material":
			errors = _request_material(params,source)
			if not errors.is_empty(): return errors
		"claim":
			var instance_id := str(params.get("instance_id", ""))
			if instance_id.is_empty() or source.is_empty() or not source.get("acknowledged", false): return PackedStringArray([DeskLocalization.source("LOC_ONLY_ACKNOWLEDGED_REAL_EVENT_PAPER_REWARDS_CAN_9A98F38C")])
			if instance_id in _state.claimed_events: return errors
			var rewards := _event_rewards(source, errors)
			if not errors.is_empty(): return errors
			var labels := PackedStringArray()
			for reward: Dictionary in rewards:
				var count := int(reward.count)
				var reward_id := str(reward.id)
				var kind := str(reward.kind)
				if card_owned(kind, reward_id): continue
				var provenance := {"source_instance_id":instance_id, "definition_id":str(source.get("definition_id", "")), "preset_id":str(source.get("design_source_preset_id", "")), "kind":kind, "id":reward_id, "count":count}
				_state.inventory_sources.append(provenance.duplicate(true))
				match kind:
					"module":
						for index in count: _grant_module(str(rules.find("modules", reward_id).kernel_id))
					_:
						_state.context_resource_inventory[reward_id] = int(_state.context_resource_inventory.get(reward_id,0)) + count
				labels.append("%s ×%d" % [str(rules.reward_resource(kind, reward_id).title), count])
			_state.claimed_events.append(instance_id)
			if not labels.is_empty(): _state.inventory_log.append(DeskLocalization.source_format("LOC_EVENT_S_S_6E3B7EEE", [instance_id, "、".join(labels)]))
		"publish":
			if source.is_empty() or not source.get("controlled", false) or not source.get("owned", false) or source.get("creator", "") != "player": return PackedStringArray([DeskLocalization.source("LOC_ONLY_PLAYER_PUBLISHED_VERSIONS_MAY_REGISTER_MODULES_C45E35C2")])
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
		"sync_draft":
			if not params.get("base") is Dictionary: return PackedStringArray([DeskLocalization.source("LOC_WRONG_DRAFT_SYNC_TYPE_EAFCB504")])
			var draft := _effect_draft(params.base, [])
			if draft.is_empty(): return PackedStringArray([DeskLocalization.source("LOC_INVALID_DRAFT_SYNC_SOURCE_437E9E98")])
			errors = _composition_errors(draft)
			if not errors.is_empty(): return errors
			_state.context_draft = draft
		_:
			return PackedStringArray([DeskLocalization.source("LOC_UNREGISTERED_DESIGN_ACTION_F210E360") + action])
	_state.operations.append({"action":action, "params":params.duplicate(true)})
	return errors

func _grant_starter_context(base: Dictionary) -> void:
	var resources: Array[String] = [_context_id("language",str(base.get("language_id",""))), _context_id("group",str(base.get("group_id","")))]
	for topic: Variant in base.get("topic_ids",[]): resources.append(_context_id("topic",str(topic)))
	for id: String in resources:
		if id.is_empty() or int(_state.context_resource_inventory.get(id,0)) > 0: continue
		var entry: Dictionary = rules.context_resource(id)
		var preset_id := str(_state.starter_preset_id)
		_state.inventory_sources.append({"source_instance_id":"starter:" + preset_id, "definition_id":"starter_contexts/" + preset_id, "preset_id":preset_id, "kind":str(entry.kind), "id":id, "count":1})
		_state.context_resource_inventory[id] = int(_state.context_resource_inventory.get(id,0)) + 1

func _grant_starter_module(preset_id: String) -> void:
	var kernel_id := str(catalog.find_preset(preset_id).kernel_id)
	if Composition.supports(preset_id):
		var definition: Dictionary = Composition.definition(preset_id)
		var preferred := "module_" + kernel_id
		if preferred not in definition.compatible_modules or not definition.requires.get(preferred,[]).is_empty():
			for id: String in definition.compatible_modules:
				if definition.requires.get(id,[]).is_empty():
					kernel_id = str(rules.find("modules",id).kernel_id)
					break
	_grant_module(kernel_id)

func _grant_module(kernel_id: String) -> void:
	var id := "module_" + kernel_id
	if rules.find("modules", id).is_empty(): return
	_state.module_inventory[id] = 1

func card_owned(kind: String, id: String) -> bool:
	if kind == "module": return int(_state.module_inventory.get(id,0)) > 0
	if kind in ["language","group","topic"]: return int(_state.context_resource_inventory.get(id,0)) > 0
	return false

func unique_event_rewards(rewards: Array, reserved_events: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for reward: Dictionary in rewards:
		var kind := str(reward.kind)
		var id := str(reward.id)
		if card_owned(kind,id): continue
		var reserved := false
		if kind in ["module","language","group","topic"]:
			for event: Dictionary in reserved_events:
				for prior: Dictionary in event.get("design_rewards",[]):
					if str(prior.kind) == kind and str(prior.id) == id: reserved = true
		if not reserved: result.append(reward.duplicate(true))
	return result

func record_publish(variant: Dictionary) -> PackedStringArray:
	return _perform("publish", {"variant_id":str(variant.get("id", ""))}, variant)

func claim_event(event: Dictionary) -> PackedStringArray:
	return _perform("claim", {"instance_id":str(event.get("instance_id", ""))}, event)

func skill_errors(id: String) -> PackedStringArray:
	var entry: Dictionary = rules.find("skills", id)
	if entry.is_empty(): return PackedStringArray([DeskLocalization.source("LOC_UNREGISTERED_SPREAD_SKILL_8953144F")])
	if id in _state.unlocked_skills: return PackedStringArray([DeskLocalization.source("LOC_THIS_SKILL_IS_ALREADY_UNLOCKED_IT_CANNOT_9F356EAA")])
	for dependency in entry.requires:
		if str(dependency) not in _state.unlocked_skills: return PackedStringArray([DeskLocalization.source("LOC_UNLOCK_REQUIRED_SKILLS_FIRST_B8C8D8A4") + str(dependency)])
	if _state.operations.size() >= RECORD_LIMIT: return PackedStringArray([DeskLocalization.source("LOC_DESIGN_ACTION_RECORD_HAS_REACHED_ITS_FINITE_37CDC932")])
	return PackedStringArray()

func supported_channels() -> Array[String]:
	var ids: Array[String] = []
	for id in _state.unlocked_skills:
		for target in rules.find("skills", str(id)).get("target_ids", []):
			if str(target) not in ids: ids.append(str(target))
	return ids

func _effect_draft(base: Dictionary, effects: Array) -> Dictionary:
	var draft: Dictionary = _canonical(base)
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
	if draft.has("context_layer_record"):
		if not draft.context_layer_record is Dictionary or _canonical(draft.context_layer_record) not in _canonical(registry.get("layer_records", [])): return false
		var fields: Dictionary = draft.context_layer_record.get("fields",{})
		for key in fields:
			if not draft.has(key):
				if key == "context_layer_attachment": return false
				continue
			if key == "political_position" and not bool(fields.get("political_known",false)) and draft[key] is Array and draft[key].is_empty(): continue
			if _canonical(draft[key]) != _canonical(fields[key]): return false
	for key in ["language_ids","group_ids"]:
		if not draft.has(key): continue
		var recorded: Dictionary = draft.get("context_layer_record",{}).get("fields",{})
		if not recorded.has(key) or _canonical(draft[key]) != _canonical(recorded[key]): return false
	if draft.has("context_layer_attachment"):
		var flags: Variant = draft.context_layer_attachment
		if not flags is Dictionary or flags.size() != 5: return false
		var recorded: Dictionary = draft.get("context_layer_record",{}).get("fields",{})
		for layer: String in ["language","group","topics","stance","pragmatic"]:
			if not flags.get(layer) is bool: return false
			if not recorded.has("context_layer_attachment") and not flags[layer]: return false
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
	return id in _state.unlocked_skills

func _strip_effects(draft: Dictionary, effects: Array) -> void:
	for effect: Dictionary in effects:
		var field := str(effect.field)
		draft[field] = clampf(float(draft[field]) - float(effect.delta), 0.0, 1.0)

func revision_base(base: Dictionary) -> Dictionary:
	var draft: Dictionary = _canonical(base)
	if not author_marks_valid(draft): return {}
	# Earlier drafts stored propagation bonuses in their author fields.
	for mark: Dictionary in draft.get("skill_effects", []):
		_strip_effects(draft, mark.get("effects", []))
	draft.erase("skill_effects")
	return draft

func apply_unlocked(base: Dictionary, _new_round: bool = false) -> PackedStringArray:
	var pristine := _state.duplicate(true)
	var draft: Dictionary = revision_base(base)
	if draft.is_empty() or not author_marks_valid(draft): return PackedStringArray([DeskLocalization.source("LOC_APPLYING_AN_ABILITY_REQUIRES_YOUR_OWN_VALID_5A5FFD6C")])
	var errors := _perform("sync_draft", {"base":draft})
	if not errors.is_empty(): _state = pristine
	return errors

func _apply_modules(base: Dictionary) -> PackedStringArray:
	var draft: Dictionary = _canonical(base)
	if not author_marks_valid(draft): return PackedStringArray([DeskLocalization.source("LOC_INVALID_EXPRESSION_PATCH_SOURCE_OR_AUTHOR_DRAFT_BDB1B39C")])
	var errors := _composition_errors(draft)
	if not errors.is_empty(): return errors
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
	if kernel == null or not draft.get("slots") is Dictionary: return PackedStringArray([DeskLocalization.source("LOC_AN_EXPRESSION_PATCH_CANNOT_REPLACE_THE_ORIGINAL_B0983DCE")])
	var record := {"record_index":_state.operations.size(), "effects":[], "suffixes":[], "modules":_state.module_slots.duplicate()}
	for module_slot in _state.module_slots.size():
		var module_id: String = str(_state.module_slots[module_slot])
		if str(module_id).is_empty(): continue
		var module: Dictionary = rules.find("modules", str(module_id))
		if not rules.module_compatible(str(draft.get("preset_id","")), module_id): return PackedStringArray([DeskLocalization.source("LOC_PATCH_INCOMPATIBLE_MEME")])
		if Composition.supports(str(draft.get("preset_id",""))) and str(_state.module_contents[module_slot]) != str(module.content): return PackedStringArray([DeskLocalization.source("LOC_COMPOSE_ERROR_PATCH")])
		var amended := _effect_draft(draft, module.draft_effects)
		if amended.is_empty(): return PackedStringArray([DeskLocalization.source("LOC_INVALID_EXPRESSION_PATCH_FIELDS_C6043637")])
		record.effects.append_array(_deltas(draft, amended, module.draft_effects))
		draft = amended
		var slot_id := str(kernel.required_slots[-1])
		var content := " · " + str(_state.module_contents[module_slot])
		draft.slots[slot_id] = str(draft.slots[slot_id]) + content
		record.suffixes.append({"slot_id":slot_id, "content":content})
	_state.module_records.append(record.duplicate(true))
	draft.module_patch_record = record
	_state.context_draft = draft
	_state.module_application = DeskLocalization.source("LOC_THE_PATCH_IS_NOW_CLIPPED_INTO_YOUR_12514443")
	return PackedStringArray()

func unlock_skill(id: String) -> PackedStringArray:
	return _perform("unlock", {"skill_id":id})

## 展示快照不复制操作历史；所有返回的容器都与权威状态隔离。
func snapshot(variants: Array = []) -> Dictionary:
	var result := {}
	for field: String in _state:
		if field in ["operations", "rules_signature"]: continue
		var value: Variant = _state[field]
		result[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	var lineage: Array[Dictionary] = []
	for variant: Dictionary in variants:
		lineage.append({"id":variant.id, "family_id":variant.family_id, "parent_ids":variant.parent_ids.duplicate(),
			"origin_ids":variant.get("origin_ids", []).duplicate(), "source_presets":variant.get("source_presets", []).duplicate(true),
			"kernel_id":variant.kernel_id, "module_id":"module_" + str(variant.kernel_id), "creator":variant.creator,
			"owned":variant.owned, "controlled":variant.controlled, "text":variant.text, "semantic_distance":variant.semantic_distance,
			"meaning":variant.get("meaning", ""), "patch_ids":variant.get("patch_ids", []).duplicate(),
			"language_versions":variant.get("language_versions", []).duplicate(true)})
	result.lineage_view = lineage
	result.supported_channels = supported_channels()
	result.available_module_inventory = _available_module_inventory()
	_snapshot_layers(result)
	result.explanation = DeskLocalization.source("LOC_THE_FIVE_BRAIN_SLICES_CARRY_LANGUAGE_AUDIENCE_F7F933BF")
	return result

func payload() -> Dictionary:
	return _state.duplicate(true)

func record_errors() -> PackedStringArray:
	return PackedStringArray([DeskLocalization.source("LOC_DESIGN_ACTION_RECORD_HAS_REACHED_ITS_FINITE_37CDC932")] if _state.operations.size() >= RECORD_LIMIT else [])

## 仅接受当前设计格式，并通过重放核对来源、扣款、资源数量和最终状态。
func validate_payload(data: Dictionary, events: Array, variants: Array, economy: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	data = _canonical(data)
	if not _integer(data.get("design_version")) or int(data.design_version) != DESIGN_VERSION or not data.get("rules_signature") is String or data.rules_signature != rules.signature() or not data.get("operations") is Array or data.operations.size() > RECORD_LIMIT:
		return PackedStringArray([DeskLocalization.source("LOC_INVALID_DESIGN_SAVE_VERSION_DEFINITIONS_OR_ACTION_1AA0AD8F")])
	var replay = get_script().new(catalog, rules)
	var published := {}
	for operation: Variant in data.operations:
		if not operation is Dictionary or not operation.get("action") is String or not operation.get("params") is Dictionary:
			errors.append(DeskLocalization.source("LOC_WRONG_DESIGN_SAVE_ACTION_TYPE_41B257AA"))
			continue
		var source := {}
		var params: Dictionary = operation.params
		if operation.action in ["claim","request_material"]:
			for event: Dictionary in events:
				if str(event.get("instance_id", "")) == str(params.get("instance_id", "")): source = event
		elif operation.action == "publish":
			var id := str(params.get("variant_id", ""))
			if published.has(id): errors.append(DeskLocalization.source("LOC_DESIGN_SAVE_GRANTS_A_PUBLICATION_MODULE_REWARD_C11AB2C0"))
			published[id] = true
			for variant: Dictionary in variants:
				if str(variant.get("id", "")) == id: source = variant
		elif operation.action == "choose_starter" and not published.is_empty(): errors.append(DeskLocalization.source("LOC_STARTING_SELECTION_MUST_PRECEDE_FIRST_PUBLICATION_01D580DD"))
		errors.append_array(replay._perform(operation.action, params, source))
	for variant: Dictionary in variants:
		if variant.get("controlled", false) and variant.get("creator", "") == "player" and not published.has(str(variant.get("id", ""))): errors.append(DeskLocalization.source("LOC_DESIGN_SAVE_LACKS_A_PLAYER_VERSION_MODULE_62FFDE84"))
	if not errors.is_empty(): return errors
	for variant: Dictionary in variants:
		if not replay.author_marks_valid(variant): errors.append(DeskLocalization.source("LOC_VERSION_EXPRESSION_PATCH_OR_ABILITY_PROVENANCE_DOES_C71016AF"))
	if _canonical(replay.payload()) != data: errors.append(DeskLocalization.source("LOC_DESIGN_SAVE_STATE_CONFLICTS_WITH_ACTION_RECORDS_139DDFEB"))
	var purchases := {}
	for transaction: Variant in economy.get("transactions", []):
		if transaction is Dictionary and str(transaction.get("reason", "")).begins_with(DeskLocalization.source("LOC_SKILL_UNLOCKED_811EF328")):
			var id := str(transaction.reason).trim_prefix(DeskLocalization.source("LOC_SKILL_UNLOCKED_811EF328"))
			var skill: Dictionary = rules.find("skills", id)
			if skill.is_empty() or id == "text" or purchases.has(id) or transaction.get("delta") != -int(skill.get("cost", -1)):
				errors.append(DeskLocalization.source("LOC_DESIGN_SAVE_SKILL_INCOME_AND_EXPENDITURE_DO_121EAB4E"))
			purchases[id] = true
	for id in _skill_ids(data):
		if id != "text" and not purchases.has(id): errors.append(DeskLocalization.source("LOC_DESIGN_SAVE_SKILL_LACKS_AN_ACTUAL_DEDUCTION_59FBBF1C"))
	if purchases.size() != _skill_ids(data).size() - 1: errors.append(DeskLocalization.source("LOC_DESIGN_SAVE_SKILLS_AND_DEDUCTION_COUNTS_DO_78EE7B1D"))
	return errors

func restore(data: Dictionary, events: Array = [], variants: Array = [], economy: Dictionary = {}) -> PackedStringArray:
	var errors := validate_payload(data, events, variants, economy)
	if errors.is_empty(): _state = _canonical(data)
	return errors

func _skill_ids(data: Dictionary) -> Array:
	return data.get("unlocked_skills", []) if data.get("unlocked_skills") is Array else []

func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func _canonical(value: Variant) -> Variant:
	# JSON 数值统一还原为设计状态使用的整数和坐标数组。
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

func request_event_material(event: Dictionary,kind: String,id: String) -> PackedStringArray:
	var pristine := _state.duplicate(true)
	var errors := _perform("request_material",{"instance_id":str(event.get("instance_id","")),"kind":kind,"id":id},event)
	if not errors.is_empty(): _state = pristine
	return errors

func _request_material(params: Dictionary,event: Dictionary) -> PackedStringArray:
	var instance_id := str(params.get("instance_id",""))
	var kind := str(params.get("kind",""))
	var id := str(params.get("id",""))
	if instance_id.is_empty() or str(event.get("instance_id","")) != instance_id: return PackedStringArray([DeskLocalization.source("LOC_A_SUPPLY_SLIP_MUST_COME_FROM_A_2BE34758")])
	for current: Dictionary in _state.event_material_claims:
		if current.source_instance_id == instance_id and current.kind == kind and current.id == id: return PackedStringArray([DeskLocalization.source("LOC_THIS_SUPPLY_SLIP_HAS_ALREADY_BEEN_TAKEN_04A289EE")])
	var errors := PackedStringArray()
	var rewards := _event_rewards(event, errors)
	if not errors.is_empty(): return errors
	var count := 0
	for reward: Dictionary in rewards:
		if str(reward.kind) == kind and str(reward.id) == id: count += int(reward.count)
	if count <= 0: return PackedStringArray([DeskLocalization.source("LOC_THE_EVENT_DOES_NOT_CONTAIN_THIS_SUPPLY_E37D2D29")])
	_state.event_material_claims.append({"source_instance_id":instance_id,"definition_id":str(event.get("definition_id","")),"preset_id":str(event.get("design_source_preset_id","")),"kind":kind,"id":id,"count":count})
	return PackedStringArray()

## 文件数组在此转为有类型的奖励记录，规则只由 MemeDesignRules 定义。
func _event_rewards(event: Dictionary, errors: PackedStringArray) -> Array[Dictionary]:
	var rewards: Array[Dictionary] = []
	var source: Variant = event.get("design_rewards")
	if not source is Array:
		errors.append(DeskLocalization.source("LOC_THE_EVENT_SUPPLIES_FIELD_MUST_BE_AN_33CCF6AA"))
		return rewards
	errors.append_array(rules.validate_event_rewards(source))
	if errors.is_empty(): rewards.assign(source)
	return rewards

func _material_requested(instance_id: String,kind: String,id: String) -> bool:
	if instance_id == "initial": return true
	var preset_id := str(_state.starter_preset_id)
	if not preset_id.is_empty() and instance_id == "starter:" + preset_id:
		var profile: Dictionary = rules.starter_contexts.get(preset_id,{})
		var entry: Dictionary = rules.context_resource(id)
		if str(entry.get("kind","")) != kind: return false
		var value := str(entry.get("value",""))
		return value in profile.get("topic_ids",[]) if kind == "topic" else (kind in ["language","group"] and value == str(profile.get(kind + "_id","")))
	for claim: Dictionary in _state.event_material_claims:
		if claim.source_instance_id == instance_id and claim.kind == kind and claim.id == id: return true
	return false

func _private_count(kind: String,id: String) -> int:
	var count := 0
	for source: Dictionary in _state.inventory_sources:
		if source.kind == kind and source.id == id and not _material_requested(str(source.source_instance_id),kind,id): count += int(source.count)
	return count

func _available_module_count(module_id: String) -> int:
	return maxi(0, int(_state.module_inventory.get(module_id, 0)) - _private_count("module", module_id))

func _available_module_inventory() -> Dictionary:
	var inventory := {}
	for module_id: String in _state.module_inventory:
		inventory[module_id] = _available_module_count(module_id)
	return inventory
