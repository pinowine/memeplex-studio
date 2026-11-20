class_name MemeDemoSimulation
extends RefCounted

signal event_raised(event: Dictionary)
signal changed
signal completed(result: Dictionary)

const WorldWar = preload("res://scripts/gameplay/events/world_war.gd")
const CompetitionState = preload("res://scripts/gameplay/competition/competition_state.gd")
const MonitorMetrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const Deviation = preload("res://scripts/gameplay/competition/meme_deviation.gd")
const Lifecycle = preload("res://scripts/gameplay/competition/meme_lifecycle.gd")
const PropagationRewards = preload("res://scripts/gameplay/economy/propagation_rewards.gd")
const DesignState = preload("res://scripts/gameplay/design/design_state.gd")
const SaveCodec = preload("res://scripts/services/persistence/save_codec.gd")
const EventScheduler = preload("res://scripts/gameplay/events/event_scheduler.gd")
const EffectRules = preload("res://scripts/gameplay/events/effect_rules.gd")
const MutationRules = preload("res://scripts/gameplay/events/mutation_rules.gd")
const EventResponse = preload("res://scripts/gameplay/events/event_response.gd")
const EventMutation = preload("res://scripts/gameplay/events/event_mutation.gd")
const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")
const AUTHOR_CONTENT_ACTIONS := ["apply_skill", "install_module", "remove_module", "edit_module_content", "install_context", "remove_context", "move_context", "move_context_axis", "move_context_axes"]

var catalog: MemeDemoCatalog
var economy := MemeDemoEconomy.new()
var design_state: MemeDemoDesignState
var hour: int = 0
var run_end_hour: int = 48
var phase: String = "draft"
var ending: Dictionary = {}
var endgame: Dictionary = {}
var speed: int = 0
var resume_speed: int = 1
var seed_value: int = 20261003
var country_id: String = ""
var country_title: String = DeskLocalization.source("LOC_NO_DEPLOYMENT_COUNTRY_SELECTED_989E9AAC")
var status: String = DeskLocalization.source("LOC_CHOOSE_A_COUNTRY_THEN_WRITE_AND_DEPLOY_4561D35F")
var latest_draft: Dictionary = {}
var families: Dictionary = {}
var variants: Array[Dictionary] = []
var deployments: Array[Dictionary] = []
var group_state: Dictionary = {}
var _meme_trends: Dictionary = {}
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
var guide_progress: Dictionary = {}
var _meme_pool_seed := -1
var _meme_pool: Array[String] = []

func _init(content: MemeDemoCatalog = null, initial_world: RefCounted = null) -> void:
	catalog = content
	design_state = DesignState.new(content)
	competition = CompetitionState.new(content)
	if catalog != null:
		reset(seed_value, initial_world)

func reset(run_seed: int, world: RefCounted = null) -> void:
	seed_value = run_seed
	_rng.seed = run_seed
	hour = 0
	run_end_hour = catalog.run_hours
	resume_speed = 1
	phase = "draft"
	ending.clear()
	endgame = {"war_started":false,"war_started_hour":-1,"carrier_country_ids":[],"collapse_hours":{}}
	speed = 0
	_serial = 0
	publish_count = 0
	current_variant_id = ""
	draft_distance = 0.0
	guide_progress.clear()
	latest_draft.clear()
	families.clear()
	variants.clear()
	deployments.clear()
	group_state.clear()
	_meme_trends.clear()
	events.clear()
	discoveries.clear()
	modifiers.clear()
	event_counts.clear()
	last_event_hours.clear()
	pending_events.clear()
	active_event = {}
	_event_clock_arrivals.clear()
	competition.reset(world)
	attention = competition.snapshot(variants,false).attention
	economy.reset(catalog.initial_meme_points)
	design_state.reset()
	for group in catalog.groups:
		group_state[str(group.id)] = {"exposed":0.0, "owned":0.0, "external":0.0, "fatigue":0.0, "trust":0.72}
	status = DeskLocalization.source_format("LOC_NEW_RUN_D_MEME_MEME_TRADING_IS_74CC0B27", economy.balance)
	changed.emit()


func candidate_meme_pool() -> Array[String]:
	if _meme_pool_seed == seed_value and not _meme_pool.is_empty(): return _meme_pool.duplicate()
	_meme_pool_seed = seed_value
	_meme_pool.clear()
	for definition: MemeDemoEvent in catalog.events:
		var id := str(definition.external_preset_id)
		if definition.origin == &"environment_meme" and id not in _meme_pool: _meme_pool.append(id)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value ^ 0x4d454d45
	for index in range(_meme_pool.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var id := _meme_pool[index]
		_meme_pool[index] = _meme_pool[other]
		_meme_pool[other] = id
	_meme_pool.resize(mini(_meme_pool.size(), random.randi_range(6, 8)))
	return _meme_pool.duplicate()

func can_add_meme(excluding_variant_id: String = "", reserved_slots: int = 0) -> bool:
	var identities := {}
	for variant: Dictionary in variants:
		if str(variant.id) == excluding_variant_id: continue
		identities[str(variant.get("meme_id", variant.id))] = true
	return identities.size() < candidate_meme_pool().size() - reserved_slots

func _external_preset_available(id: String) -> bool:
	# Leave room for a player revision to become an independent meme.
	if id not in candidate_meme_pool() or not can_add_meme("", 1): return false
	for variant: Dictionary in variants:
		if str(variant.get("preset_id", "")) == id and variant.get("parent_ids", []).is_empty(): return false
	return true

func _eligible_events() -> Array[MemeDemoEvent]:
	var result: Array[MemeDemoEvent] = []
	for definition: MemeDemoEvent in catalog.events:
		if definition.origin != &"environment_meme" or _external_preset_available(str(definition.external_preset_id)): result.append(definition)
	return result

func gameplay_mode() -> String:
	return "world_competition"

func queue_guidance(id: String, source_id: String) -> bool:
	if guide_progress.has(id) or not guidance_source_valid(id,source_id,events,variants): return false
	guide_progress[id] = {"source_id":source_id,"shown":false}
	return true

func mark_guidance_shown(id: String) -> bool:
	if not guide_progress.has(id) or bool(guide_progress[id].shown): return false
	# Consumed guidance includes a real presentation or an explicit settings opt-out.
	guide_progress[id].shown = true
	return true

func guidance_progress() -> Dictionary:
	return guide_progress.duplicate(true)

static func guidance_source_valid(id: String, source_id: String, event_rows: Array, variant_rows: Array) -> bool:
	if id == "deviation":
		for variant: Dictionary in variant_rows:
			if str(variant.id) == source_id: return bool(Lifecycle.content(variant).get("controlled", false))
		return false
	if id == "fax":
		for event: Dictionary in event_rows:
			if str(event.get("instance_id","")) == source_id: return true
		return false
	if id not in ["competition","mutation"]: return false
	for variant: Dictionary in variant_rows:
		if str(variant.get("id","")) != source_id: continue
		if str(variant.get("creator","")) == "player" or bool(variant.get("controlled",false)): return false
		if id == "competition": return variant.get("origin_ids",[]).is_empty()
		if bool(variant.get("deviation_split", false)): return true
		return not variant.get("origin_ids",[]).is_empty() and not variant.get("parent_ids",[]).is_empty() and not str(variant.get("source_event","")).is_empty()
	return false

func bind_world(world: RefCounted, settings: Resource) -> PackedStringArray:
	if publish_count > 0: return PackedStringArray([DeskLocalization.source("LOC_THE_WORLD_CANNOT_BE_REPLACED_AFTER_FIRST_58DB6321")])
	return competition.bind_world(world,settings)

func _required_context_errors() -> PackedStringArray:
	return design_state.required_context_errors()

## Presentation includes the saved fraction between discrete simulation ticks.
func elapsed_hours() -> float:
	return float(hour) + float(competition._state.hour_credit)

func advance_active_seconds(delta: float) -> int:
	if phase != "running" or speed == 0 or not is_finite(delta) or delta <= 0.0: return 0
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
	var defaults := {"channel_id":"local_board" if find_channel("local_board") != null else str(catalog.channels[0].id),
		"target":preset.title, "remix_cost":0.3, "context_dependency":0.5, "reuse_permission":&"unknown",
		"language_access":0.8, "recognizability":0.8}
	defaults.merge(design_state.rules.starter_contexts.get(preset_id,{}), true)
	defaults.merge(base, true)
	for field in ["political_position","pragmatic_position"]:
		var point: Variant = defaults.get(field)
		if point is Array and point.size() == 2: defaults[field] = Vector2(float(point[0]),float(point[1]))
	defaults.topic_ids = PackedStringArray(defaults.get("topic_ids",[]))
	return preset.to_draft(defaults)

func design_action(action: String, params: Dictionary = {}) -> PackedStringArray:
	if bool(endgame.war_started) or phase == "complete": return PackedStringArray([DeskLocalization.source("LOC_WAR_NO_REVISION")])
	if action == "choose_starter" and (publish_count > 0 or phase != "draft"):
		return PackedStringArray([DeskLocalization.source("LOC_A_DEPLOYED_RUN_CANNOT_SELECT_A_DIFFERENT_1172A7D4")])
	if action == "choose_starter":
		params = params.duplicate(true)
		params.base = _encoded_draft(starter_draft(str(params.get("preset_id",""))))
	if action == "move_module":
		if not params.get("position") is Vector2: return PackedStringArray([DeskLocalization.source("LOC_PATCH_PLACEMENT_REQUIRES_PAPER_LOCAL_COORDINATES_FC1D71FE")])
		params = params.duplicate(true)
		params.position = _vector_array(params.position)
	if action in AUTHOR_CONTENT_ACTIONS:
		var draft: Variant = params.get("draft")
		if not draft is Dictionary or not draft.get("slots") is Dictionary or not draft.get("political_position") is Vector2 or not draft.get("pragmatic_position") is Vector2:
			return PackedStringArray([DeskLocalization.source("LOC_APPLYING_A_SOLID_REQUIRES_A_VALID_AUTHOR_CAF24FE0")])
		for key in ["remix_cost", "context_dependency", "language_access", "recognizability"]:
			if not _number(draft.get(key)): return PackedStringArray([DeskLocalization.source("LOC_AN_AUTHOR_DRAFT_NUMERIC_VALUE_HAS_THE_CCD0F240")])
		var draft_errors := PackedStringArray() if action in ["install_context","remove_context","move_context","move_context_axis", "move_context_axes"] else validate_draft(draft)
		draft_errors.append_array(_core_errors(draft))
		if not draft_errors.is_empty(): return draft_errors
		var encoded: Dictionary = draft.duplicate(true)
		for key in ["political_position", "pragmatic_position"]: encoded[key] = _vector_array(encoded[key])
		for key in ["replaceable_slots", "topic_ids"]:
			if encoded.has(key): encoded[key] = Array(encoded[key])
		if not current_variant_id.is_empty():
			encoded.community_changes = ExpressionText.Community.collect(encoded.get("community_changes", []), variant_by_id(current_variant_id), variants)
		params = params.duplicate(true)
		params.erase("draft")
		params.base = encoded
	var errors: PackedStringArray = design_state.perform(action, params)
	if errors.is_empty():
		if action in AUTHOR_CONTENT_ACTIONS: _sync_live_author_content()
		changed.emit()
	return errors

func _live_author_content(draft: Dictionary, skills: Array, source: Dictionary) -> Dictionary:
	var data := draft.duplicate(true)
	data.patch_ids = ExpressionText.patch_ids(data)
	data.flow_skill_ids = skills.duplicate()
	var composed := ExpressionText.compose(catalog, data)
	var result := {"text":str(composed.expression), "patch_ids":data.patch_ids.duplicate(), "flow_draft":_encoded_draft(data), "flow_profile":competition.profile(data)}
	for field: String in ["meaning", "meaning_id", "language_versions"]: result[field] = composed[field]
	for field: String in ["language_id", "topic_ids", "political_known", "political_position", "pragmatic_position"]: result[field] = result.flow_draft[field]
	var identity := Lifecycle.content(source)
	for field: String in ["creator", "owned", "controlled"]: result[field] = identity[field]
	result.semantic_distance = MonitorMetrics.deviation(source.deviation_anchor, result)
	return result

func _sync_live_author_content() -> void:
	if current_variant_id.is_empty(): return
	var source := variant_by_id(current_variant_id)
	var draft := context_draft()
	var state := design_state.payload()
	# The author edits one live meme; its birth revision remains immutable.
	source.effective_content = _live_author_content(draft, state.unlocked_skills, source)
	source.live_author_edit = {"schema":1, "operation_count":state.operations.size(), "hour":hour}
	competition.set_effective_profile(current_variant_id, source.effective_content.flow_profile)
	latest_draft = draft.duplicate(true)
	draft_distance = float(source.effective_content.semantic_distance)
	if phase == "draft": phase = "running"
	competition.record_author_edit(variants, current_variant_id, country_id, hour)
	_check_deviation(source)

func deviation_threshold(raw: Dictionary) -> float:
	var live := Lifecycle.content(raw)
	live.flow_profile = competition.live_profile(str(raw.id))
	return competition.propagation_rules.split_threshold(MonitorMetrics.SPLIT_THRESHOLD, live, {"flow_draft":live.get("flow_draft", {})})

func _advance_deviation() -> void:
	for raw: Dictionary in variants.duplicate():
		var live := Lifecycle.content(raw)
		if bool(raw.get("retired", false)) or not bool(live.get("controlled", false)): continue
		var skills: Array = competition.live_profile(str(raw.id)).get("skill_ids", [])
		var delta := Deviation.hourly_growth(skills, str(live.get("preset_id", "")))
		var floor_pressure := -Deviation.raw_semantic(raw.deviation_anchor, live)
		raw.deviation_pressure = maxf(floor_pressure, float(raw.get("deviation_pressure", 0.0)) + delta)
		_check_deviation(raw)

func _check_deviation(raw: Dictionary) -> void:
	var live := Lifecycle.content(raw)
	if Deviation.total(raw.deviation_anchor, live) <= deviation_threshold(raw) or not can_add_meme(): return
	var child := Lifecycle.revision_snapshot(raw)
	child.id = _new_id("variant")
	child.parent_ids = [str(raw.id)]
	child.creator = "community"
	child.owned = false
	child.controlled = false
	child.semantic_distance = 0.0
	child.deviation_split = true
	child.erase("live_author_edit")
	child.erase("source_event")
	child.mutation_parent_content = Lifecycle.revision_snapshot(raw)
	variants.append(child)
	_register_external_world(child)
	if str(raw.id) == current_variant_id:
		if raw.has("live_author_edit"):
			raw.live_author_edit.hour = hour
		else:
			design_state.restore_meme(Lifecycle.content(raw).flow_draft)
		latest_draft = context_draft()
	queue_guidance("mutation", str(child.id))

func context_draft() -> Dictionary:
	var draft: Dictionary = design_state.context_draft()
	if not current_variant_id.is_empty():
		var active := Lifecycle.content(variant_by_id(current_variant_id))
		if bool(active.get("owned", false)):
			draft.community_changes = ExpressionText.Community.collect(draft.get("community_changes", []), variant_by_id(current_variant_id), variants)
	for key in ["political_position", "pragmatic_position"]:
		if draft.has(key): draft[key] = Vector2(draft[key][0], draft[key][1])
	for key in ["replaceable_slots", "topic_ids"]:
		if draft.has(key): draft[key] = PackedStringArray(draft[key])
	return draft

func request_event_material(instance_id: String, kind: String, id: String) -> PackedStringArray:
	for event: Dictionary in events:
		if str(event.instance_id) != instance_id: continue
		if not bool(event.get("acknowledged",false)) and (phase != "event" or str(active_event.get("instance_id","")) != instance_id): return PackedStringArray([DeskLocalization.source("LOC_ONLY_THE_CURRENT_EVENT_S_OR_AN_A0E6D124")])
		var errors: PackedStringArray = design_state.request_event_material(event,kind,id)
		if errors.is_empty(): changed.emit()
		return errors
	return PackedStringArray([DeskLocalization.source("LOC_THIS_SUPPLY_SLIP_HAS_NO_EVENT_SOURCE_7B92D1B9")])

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
		return PackedStringArray([DeskLocalization.source("LOC_THE_CONFIRMED_BASE_FORM_CANNOT_BE_CHANGED_7215DF53")])
	return PackedStringArray()

func _encoded_draft(draft: Dictionary) -> Dictionary:
	var encoded := draft.duplicate(true)
	for key in ["political_position", "pragmatic_position"]:
		if encoded.get(key) is Vector2: encoded[key] = _vector_array(encoded[key])
	for key in ["replaceable_slots", "topic_ids"]:
		if encoded.has(key): encoded[key] = Array(encoded[key])
	return encoded

func propagation_research_ready() -> bool:
	return economy.rewarded_keys.has("propagation:first_adoption")

func ensure_text_propagation() -> PackedStringArray:
	if "text" in design_state.snapshot().unlocked_skills: return PackedStringArray()
	return buy_propagation_skill("text", context_draft())

func configure_propagation_route(source_country: String, target_country: String) -> PackedStringArray:
	var errors: PackedStringArray = competition.configure_route(source_country, target_country, current_variant_id)
	if errors.is_empty(): status = DeskLocalization.source("LOC_PROP_RELAY_CONFIGURED")
	changed.emit()
	return errors

func buy_propagation_skill(id: String, draft: Dictionary = {}) -> PackedStringArray:
	if bool(endgame.war_started) or phase == "complete": return PackedStringArray([DeskLocalization.source("LOC_WAR_NO_REVISION")])
	if id != "text" and not propagation_research_ready():
		return PackedStringArray([DeskLocalization.source("LOC_PROP_RESEARCH_READY")])
	var errors: PackedStringArray = design_state.skill_errors(id)
	if not errors.is_empty(): return errors
	var cost: int = int(design_state.rules.find("skills", id).cost)
	var reserve: int = catalog.first_publish_cost if publish_count == 0 else 0
	if economy.balance - cost < reserve:
		return PackedStringArray([DeskLocalization.source_format("LOC_NOT_ENOUGH_MEME_RESERVE_D_FOR_FIRST_FE60303F", reserve)])
	var candidate: MemeDemoDesignState = DesignState.new(catalog)
	candidate._state = design_state.payload()
	errors = candidate.unlock_skill(id)
	if not errors.is_empty(): return errors
	if draft.is_empty():
		draft = latest_draft.duplicate(true)
		if draft.is_empty() and not str(candidate.snapshot().starter_preset_id).is_empty(): draft = starter_draft(str(candidate.snapshot().starter_preset_id))
	if not draft.is_empty():
		if not current_variant_id.is_empty():
			draft = draft.duplicate(true)
			draft.community_changes = ExpressionText.Community.collect(draft.get("community_changes", []), variant_by_id(current_variant_id), variants)
		errors = validate_draft(draft)
		errors.append_array(_core_errors(draft))
		if not errors.is_empty(): return errors
		errors = candidate.apply_unlocked(_encoded_draft(draft))
		if not errors.is_empty(): return errors
	elif not candidate.rules.find("skills", id).get("draft_effects", []).is_empty(): return PackedStringArray([DeskLocalization.source("LOC_CONFIRM_YOUR_OWN_MEME_DRAFT_FIRST_C8D61D07")])
	if not economy.charge(cost, DeskLocalization.source_format("%s%s", ["LOC_SKILL_UNLOCKED_811EF328", id], [0]), hour): return PackedStringArray([DeskLocalization.source("LOC_NOT_ENOUGH_MEME_89E627E2")])
	economy.transactions.back().propagation_skill_id = id
	design_state = candidate
	competition.set_live_skills(Array(design_state.snapshot().unlocked_skills), variants)
	if not current_variant_id.is_empty():
		var raw := variant_by_id(current_variant_id)
		raw.deviation_pressure = float(raw.get("deviation_pressure", 0.0)) - float(Deviation.RESEARCH_RELIEF.get(id, 0.0))
	_sync_live_author_content()
	changed.emit()
	return errors

func bind_country(id: String, title: String) -> void:
	if bool(endgame.war_started) or phase == "complete": return
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
		errors.append(DeskLocalization.source("LOC_UNREGISTERED_BASE_FORM_AA1FA4DA"))
		return errors
	var preset_id := str(data.get("preset_id", ""))
	if not preset_id.is_empty():
		var preset := catalog.find_preset(preset_id)
		if preset == null:
			errors.append(DeskLocalization.source("LOC_UNREGISTERED_PRESET_FAMILY_FA4A166F"))
		elif preset.kernel_id != kernel.id:
			errors.append(DeskLocalization.source("LOC_PRESET_FAMILY_DOES_NOT_MATCH_THE_BASE_02D496A9"))
	var slots: Dictionary = data.get("slots", {})
	for slot in kernel.required_slots:
		if str(slots.get(slot, "")).strip_edges().is_empty():
			errors.append(DeskLocalization.source("LOC_MISSING_SEMANTIC_SLOT_321D840F") + slot)
	if find_channel(str(data.get("channel_id", ""))) == null:
		errors.append(DeskLocalization.source("LOC_UNREGISTERED_TRANSMISSION_CHANNEL_60325BA7"))
	var group_found := false
	for group in catalog.groups:
		group_found = group_found or str(group.id) == str(data.get("group_id", ""))
	if not group_found and not str(data.get("group_id", "")).is_empty():
		errors.append(DeskLocalization.source("LOC_UNREGISTERED_INITIAL_AUDIENCE_62693555"))
	if str(data.get("target", "")).strip_edges().is_empty():
		errors.append(DeskLocalization.source("LOC_ENTER_THE_TARGET_YOU_SUPPORT_OR_OPPOSE_206B04DC"))
	for key in ["remix_cost", "context_dependency", "language_access", "recognizability"]:
		var number: float = float(data.get(key, -1.0))
		if not is_finite(number) or number < 0.0 or number > 1.0:
			errors.append(key + DeskLocalization.source("LOC_MUST_BE_IN_THE_RANGE_9414D40B"))
	for key in ["political_position", "pragmatic_position"]:
		var position: Vector2 = data.get(key, Vector2.ZERO)
		if not is_finite(position.x) or not is_finite(position.y) or absf(position.x) > 1.0 or absf(position.y) > 1.0:
			errors.append(key + DeskLocalization.source("LOC_COORDINATE_IS_OUT_OF_RANGE_5D6ACB76"))
	var replaceable_seen: Dictionary = {}
	for slot in PackedStringArray(data.get("replaceable_slots", [])):
		if slot not in kernel.required_slots: errors.append(DeskLocalization.source("LOC_UNREGISTERED_REPLACEABLE_SLOT_12819029") + slot)
		if replaceable_seen.has(slot): errors.append(DeskLocalization.source("LOC_DUPLICATE_REPLACEABLE_SLOT_CFF77B80") + slot)
		replaceable_seen[slot] = true
	if str(data.get("reuse_permission", "unknown")) not in ["allowed", "conditional", "restricted", "unknown"]:
		errors.append(DeskLocalization.source("LOC_UNREGISTERED_REUSE_PERMISSION_2B61EEA0"))
	var topics := PackedStringArray(data.get("topic_ids", []))
	for topic in topics:
		if topic not in catalog.topics: errors.append(DeskLocalization.source("LOC_UNREGISTERED_TOPIC_F5347B52") + topic)
	if ExpressionText.Composition.supports(preset_id):
		errors.append_array(ExpressionText.Composition.validate(data, ExpressionText.patch_ids(data)))
	return errors

## 校验来源、语境和费用后投放；外部版本不获得作者控制权。
func publish(data: Dictionary) -> PackedStringArray:
	if bool(endgame.war_started) or phase == "complete": return PackedStringArray([DeskLocalization.source("LOC_WAR_NO_REVISION")])
	if "text" not in design_state.snapshot().unlocked_skills:
		return PackedStringArray([DeskLocalization.source("LOC_PROP_TEXT_REQUIRED")])
	var errors := validate_draft(data)
	var patch_ids := MutationRules.authored_patch_ids(data)
	errors.append_array(catalog.DESIGN_RULES.patch_errors(str(data.get("preset_id", "")), patch_ids))
	if data.has("patch_ids") and data.patch_ids != patch_ids: errors.append("Player patches must match the author record")
	errors.append_array(_required_context_errors())
	errors.append_array(_core_errors(data))
	errors.append_array(design_state.record_errors())
	errors.append_array(design_state.layer_errors(_encoded_draft(data)))
	if not design_state.author_marks_valid(data): errors.append(DeskLocalization.source("LOC_EXPRESSION_PATCHES_AND_ABILITY_RECORDS_MUST_COME_2C544266"))
	if not str(design_state.snapshot().starter_preset_id).is_empty() and str(data.get("channel_id", "")) not in design_state.supported_channels():
		errors.append(DeskLocalization.source("LOC_THIS_CHANNEL_S_SUPPORT_ABILITY_HAS_NOT_ED9790A4"))
	if phase != "draft":
		errors.append(DeskLocalization.source("LOC_RETURN_TO_THE_WORKBENCH_AND_CREATE_YOUR_1A4056D3"))
	if not competition.has_country(country_id): errors.append(DeskLocalization.source("LOC_THE_DEPLOYMENT_COUNTRY_IS_NOT_IN_THE_9557C167"))
	if country_id.is_empty():
		errors.append(DeskLocalization.source("LOC_SELECT_A_DEPLOYMENT_COUNTRY_ON_THE_MAP_AA28A76D"))
	var cost: int = catalog.first_publish_cost
	if economy.balance < cost:
		errors.append(DeskLocalization.source_format("LOC_NOT_ENOUGH_MEME_NEED_D_HAVE_D_46321C6B", [cost, economy.balance]))
	if not errors.is_empty():
		status = DeskLocalization.source_join("；",errors)
		changed.emit()
		return errors
	var pristine := _capture_lifecycle_state()
	# Publication and distribution commit together after validation.
	economy.charge(cost, DeskLocalization.source("LOC_FIRST_DEPLOYMENT_23FC9181"), hour)
	var kernel := find_kernel(str(data.kernel_id))
	var preset_id := str(data.get("preset_id", ""))
	var preset := catalog.find_preset(preset_id)
	var source_presets: Array = [preset.source_record()] if preset != null else []
	var anchor := preset.family_anchor if preset != null else kernel.family_anchor
	var family_id := _new_id("family")
	var parent_ids: Array[String] = []
	families[family_id] = {"id":family_id, "owner":"player", "anchor":anchor, "split_threshold":MonitorMetrics.SPLIT_THRESHOLD, "derived_from":[], "preset_id":preset_id, "source_presets":source_presets.duplicate(true)}
	var id := _new_id("variant")
	var composed: Dictionary = ExpressionText.compose(catalog, data)
	var text: String = str(composed.expression)
	variants.append({"id":id, "family_id":family_id, "parent_ids":parent_ids, "origin_ids":[id], "creator":"player", "owned":true, "controlled":true, "text":text, "kernel_id":str(kernel.id), "preset_id":preset_id, "source_presets":source_presets.duplicate(true), "semantic_distance":0.0, "language_id":str(data.language_id), "pragmatic_position":_vector_array(data.pragmatic_position), "political_position":_vector_array(data.political_position) if data.get("political_known", false) else [], "target":str(data.target), "topic_ids":Array(data.get("topic_ids", []))})
	variants.back().patch_ids = patch_ids.duplicate()
	for field: String in ["meaning", "meaning_id", "language_versions"]: variants.back()[field] = composed[field]
	for field in ["module_patch_record", "skill_effects", "context_layer_record"]:
		if data.has(field): variants.back()[field] = data[field].duplicate(true)
	var profile_draft := data.duplicate(true)
	profile_draft.patch_ids = patch_ids.duplicate()
	profile_draft.flow_skill_ids = design_state.snapshot().unlocked_skills.duplicate()
	variants.back().flow_draft = _encoded_draft(profile_draft)
	variants.back().flow_profile = competition.profile(profile_draft)
	competition.register(variants.back(),variants.back().flow_profile,country_id,hour)
	design_state.record_publish(variants.back())
	var activation: Dictionary = Lifecycle.new(self).activate(variants.back())
	if activation.has("error"):
		_restore_lifecycle_state(pristine)
		status = str(activation.error)
		changed.emit()
		return PackedStringArray([status])
	current_variant_id = id
	latest_draft = data.duplicate(true)
	draft_distance = 0.0
	competition.record_publication(variants, current_variant_id, country_id, hour)
	publish_count += 1
	deployments.append({"id":_new_id("deployment"), "variant_id":id, "country_id":country_id, "group_id":str(data.group_id), "channel_id":str(data.channel_id), "hour":hour})
	phase = "running"
	speed = 1
	status = DeskLocalization.source_format("LOC_DEPLOYED_TO_S_LATER_EXTERNAL_VERSIONS_CANNOT_CAE6EE96", country_title, [0])
	changed.emit()
	return errors

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
	_advance_deviation()
	if bool(endgame.war_started):
		_advance_world_war()
	else:
		_produce_event_memes()
		_spread_world()
		var result: Dictionary = competition.evaluate_ending(variants, hour, current_variant_id, country_id)
		if not result.is_empty():
			_finish(result)
		elif hour >= ceili(catalog.gameplay_rules.fallback_war_seconds * catalog.gameplay_rules.hours_per_active_second):
			_start_world_war()
		else:
			_schedule_events()
			_open_next_event()
	changed.emit()
	return true

func _expire_modifiers() -> void:
	for index in range(modifiers.size() - 1, -1, -1):
		if hour >= float(modifiers[index].expires):
			modifiers.remove_at(index)

func _spread_world() -> void:
	var factors := {}
	var runtime_modifiers := _runtime_modifiers()
	for country: Dictionary in catalog.gameplay_rules.countries:
		var cid := str(country.id)
		factors[cid] = {}
		for variant: Dictionary in competition.active_variants(variants):
			var entry: Dictionary = competition._state.registry[str(variant.id)]
			var profile: Dictionary = competition.live_profile(str(variant.id))
			profile.topic_ids = Array(competition.active_topics(profile))
			factors[cid][str(variant.id)] = _audience_factor(profile) * EffectRules.country_factor(runtime_modifiers, hour, cid, str(variant.id), profile)
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
	_produce_template_variants()
	_reward_milestones()

func _audience_factor(profile: Dictionary) -> float:
	var ids: Array = profile.get("group_ids", [str(profile.group_id)]).duplicate()
	ids.sort()
	var seen := {}
	var total := 0.0
	for id: String in ids:
		if seen.has(id): continue
		seen[id] = true
		var state: Dictionary = group_state.get(id, {"trust":0.72, "fatigue":0.0})
		total += EffectRules.attraction_factor(modifiers, hour, id, competition.active_topics(profile)) * maxf(0.05, float(state.trust)) * maxf(0.05, 1.0 - float(state.fatigue))
	return total / seen.size()

func _register_external_world(variant: Dictionary, event_country: String = "") -> Dictionary:
	var parent_id: String = str(variant.parent_ids[0]) if not variant.parent_ids.is_empty() else ""
	var profile_data: Dictionary = competition.inherited_profile(variant,parent_id)
	variant.flow_profile = profile_data.duplicate(true)
	var origin: String = str(competition._state.registry.get(parent_id,{}).get("origin_country",""))
	if not event_country.is_empty(): origin = event_country
	competition.register(variant,profile_data,origin,hour)
	var source := variant_by_id(parent_id) if not parent_id.is_empty() else {}
	return Lifecycle.new(self).activate(variant, source)

func _reward_milestones() -> void:
	var totals := totals_state()
	var origin_cid: String = str(deployments[0].country_id) if not deployments.is_empty() else country_id
	var origin_population := int(catalog.gameplay_rules.country(origin_cid).get("population", 40000000))
	var landed := 0
	var active: Array = competition.active_variants(variants)
	var unlocked: Array = design_state.snapshot().unlocked_skills
	for row: Dictionary in competition._state.world:
		var cid := str(row.id)
		var adopted := 0
		var country: Dictionary = competition._state.countries[cid]
		var threshold := maxi(1, floori(float(row.population) * 0.05))
		for variant: Dictionary in active:
			var count := int(country.adopted.get(str(variant.id), 0))
			if bool(variant.owned): adopted += count
			if "derivative_backlink" in unlocked and not bool(variant.controlled) and not variant.get("origin_ids", []).is_empty() and count >= threshold:
				var backlink_key := "backlink:%s:%s" % [str(variant.get("meme_id", variant.id)), cid]
				economy.reward(backlink_key, 8, DeskLocalization.source("LOC_PROP_BACKLINK_RETURN"), hour)
		if adopted >= threshold: landed += 1
	var first_hour: int = int(deployments[0].hour) if not deployments.is_empty() else hour
	for reward: Dictionary in PropagationRewards.due_rewards(hour, first_hour, int(totals.owned_adopted), origin_population, landed, economy.transactions, economy.rewarded_keys):
		var reason := DeskLocalization.source_format(str(reward.reason_key), reward.get("reason_inputs", [])) if not reward.get("reason_inputs", []).is_empty() else DeskLocalization.source(str(reward.reason_key))
		if economy.reward(str(reward.key), int(reward.amount), reason, hour):
			economy.transactions.back().merge(reward.ledger_fields, true)

func _produce_template_variants() -> void:
	var unlocked: Array = design_state.snapshot().unlocked_skills
	var period := 36 if "free_remix" in unlocked else (48 if "public_template" in unlocked else 0)
	if period == 0 or hour <= 0 or hour % period != 0: return
	for raw: Dictionary in competition.active_variants(variants):
		var parent: Dictionary = Lifecycle.revision_snapshot(raw)
		parent.flow_profile = competition.live_profile(str(raw.id))
		if parent.get("origin_ids", []).is_empty() or not parent.get("flow_profile") is Dictionary: continue
		if not competition.propagation_rules.can_template(parent.flow_profile): continue
		var host := ""
		for row: Dictionary in competition._state.world:
			if int(competition._state.countries[str(row.id)].adopted.get(str(parent.id), 0)) > 0:
				host = str(row.id)
				break
		if host.is_empty(): continue
		var mutation: Dictionary = MutationRules.candidate(catalog, parent)
		if mutation.is_empty(): continue
		var duplicate := false
		for item: Dictionary in variants:
			if item.get("origin_ids", []) == parent.origin_ids and str(item.get("text", "")) == str(mutation.composition.expression) and str(item.get("meaning_id", "")) == str(mutation.composition.meaning_id): duplicate = true
		if duplicate: continue
		var pristine := _capture_lifecycle_state()
		var previous_count := variants.size()
		_spawn_remix("", str(parent.flow_profile.group_id), "", str(parent.id), host, true)
		if variants.size() <= previous_count: continue
		var activation := _register_external_world(variants.back(), host)
		if activation.has("error"):
			_restore_lifecycle_state(pristine)
			status = str(activation.error)
			return
		attention = competition.snapshot(variants, false).attention
		status = DeskLocalization.source("LOC_PROP_TEMPLATE_REUSE")
		return


func totals_state(view: Dictionary = {}) -> Dictionary:
	if view.is_empty(): view = competition.snapshot(variants,false)
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

# Deferred arrivals keep their place without printing a burst when conditions become eligible.
func _schedule_events() -> void:
	var arrivals := EventScheduler.arrival_count(catalog.event_clock, seed_value, hour, _event_clock_arrivals)
	if events.size() >= arrivals: return
	if not events.is_empty() and hour - int(events[-1].hour) < catalog.event_clock.minimum_interval_hours(): return
	if not deployments.is_empty() and hour <= 120:
		var correspondent := _foreign_correspondent_event()
		if not correspondent.is_empty():
			_execute_event(correspondent.definition, str(correspondent.country_id))
			return
	if hour >= 420 and _needs_major_competitor():
		var major := _choose_major_competitor_event()
		if not major.is_empty():
			_execute_event(major.definition, str(major.country_id))
			return
	var contributions := _event_country_contributions()
	var cid := _sample_event_country(EventScheduler.country_weights(contributions))
	var definition := EventScheduler.choose_event(_eligible_events(), hour, catalog.gameplay_rules.event_time_scale,
		event_counts, last_event_hours, _event_condition_values(), _rng, catalog.gameplay_rules.country(cid), float(contributions[cid]) > 0.0)
	if definition != null: _execute_event(definition, cid)

func _foreign_correspondent_event() -> Dictionary:
	var origin_cid := str(deployments[0].country_id)
	var primary_langs: Array = catalog.gameplay_rules.country(origin_cid).get("primary_languages", [])
	if primary_langs.is_empty(): return {}
	var needed_cards: Array[String] = []
	for lang: Variant in primary_langs:
		var card_id := "language_" + str(lang)
		if design_state.card_owned("language", card_id): return {}
		for existing: Dictionary in events:
			for reward: Dictionary in existing.get("design_rewards", []):
				if str(reward.get("kind", "")) == "language" and str(reward.get("id", "")) == card_id: return {}
		needed_cards.append(card_id)
	var fallback: MemeDemoEvent = null
	for definition: MemeDemoEvent in _eligible_events():
		for reward: Dictionary in definition.design_rewards:
			if str(reward.get("kind", "")) == "language" and str(reward.get("id", "")) in needed_cards:
				if definition.origin == &"world":
					return {"definition":definition, "country_id":origin_cid}
				if fallback == null and not _event_target(origin_cid, definition).is_empty():
					fallback = definition
	return {"definition":fallback, "country_id":origin_cid} if fallback != null else {}

func _needs_major_competitor() -> bool:
	var view: Dictionary = competition.snapshot(variants, false)
	for row: Dictionary in view.variants:
		if bool(row.lineage) or bool(row.controlled): continue
		if float(row.monitor_spread) >= catalog.gameplay_rules.duel_spread_min: return false
		var origin := str(row.origin_country)
		var birth := int(competition._state.registry.get(str(row.id), {}).get("birth_hour", -1000))
		if int(catalog.gameplay_rules.country(origin).get("population", 0)) >= 55000000 and hour - birth < 240:
			return false
	return true

func _choose_major_competitor_event() -> Dictionary:
	var major_countries: Array[String] = []
	for row: Dictionary in catalog.gameplay_rules.countries:
		if int(row.population) >= 55000000: major_countries.append(str(row.id))
	if major_countries.is_empty(): return {}
	var cid: String = major_countries[_rng.randi_range(0, major_countries.size() - 1)]
	var env_defs: Array[MemeDemoEvent] = []
	for definition: MemeDemoEvent in _eligible_events():
		if definition.origin == &"environment_meme": env_defs.append(definition)
	if env_defs.is_empty(): return {}
	var chosen := EventScheduler.choose_event(env_defs, hour, catalog.gameplay_rules.event_time_scale,
		event_counts, last_event_hours, _event_condition_values(), _rng, catalog.gameplay_rules.country(cid), true)
	return {"definition":chosen, "country_id":cid} if chosen != null else {}

## 统一创建事件身份、应用效果并登记来源，界面只接收记录副本。
func _execute_event(definition: MemeDemoEvent, occurring_country: String = "") -> void:
	if definition.origin == &"environment_meme" and not _external_preset_available(str(definition.external_preset_id)): return
	var pristine := _capture_lifecycle_state()
	var id := str(definition.id)
	var cid := occurring_country if not occurring_country.is_empty() else _event_country(definition)
	if cid.is_empty(): return
	var country: Dictionary = catalog.gameplay_rules.country(cid)
	var title := _event_country_title(cid)
	var response := EventResponse.resolve(definition, country, catalog.groups)
	var target := _event_target(cid, definition) if definition.origin == &"transmission" else {}
	if definition.origin == &"transmission" and target.is_empty(): return
	if definition.origin == &"transmission": response.topic_ids = Array(target.topic_ids)
	var event_id := _new_id("event")
	var first_variant: int = variants.size()
	var observed := PackedStringArray()
	var applied: Array[Dictionary] = []
	var duration := maxf(1.0, _event_hours(definition.attention_duration_hours))
	var response_modifier := _event_modifier(event_id, definition, cid, duration)
	response_modifier.effect_id = "response"
	response_modifier.response = response.duplicate(true)
	if definition.origin == &"transmission":
		response_modifier.variant_ids = [str(target.id)]
		response_modifier.topics = []
	modifiers.append(response_modifier)
	for effect: MemeDemoEffect in definition.effects:
		var row := {"effect_id":str(effect.effect_id), "amount":effect.amount, "duration_hours":maxf(1.0, _event_hours(effect.duration_hours)), "group_ids":Array(effect.group_ids), "country_id":cid, "target_variant_id":str(target.get("id", ""))}
		applied.append(row)
		var modifier := _event_modifier(event_id, definition, cid, float(row.duration_hours))
		modifier.effect_id = str(effect.effect_id)
		modifier.amount = -effect.amount if effect.effect_id == &"fatigue" else effect.amount
		modifier.groups = Array(effect.group_ids)
		modifier.variant_ids = [str(target.id)]
		modifier.topics = []
		match str(effect.effect_id):
			"deviation":
				var affected := variant_by_id(_active_variant_id(str(target.id)))
				var delta := effect.amount
				if str(affected.get("preset_id", "")) == "versailles_2020": delta *= 1.25
				if delta > 0.0 and "usage_example" in design_state.snapshot().unlocked_skills: delta *= 0.65
				affected.deviation_pressure = maxf(-0.2, float(affected.get("deviation_pressure", 0.0)) + delta)
			"remix":
				if effect.amount > 0.0: observed.append(_spawn_remix(event_id, str(effect.group_ids[0]) if not effect.group_ids.is_empty() else str(target.flow_profile.group_id), id, str(target.id), cid))
			"adoption": competition.adoption_pulse(_active_variant_id(str(target.id)), effect.amount, cid)
			"revival":
				modifier.amount = effect.amount
				modifiers.append(modifier)
			_: modifiers.append(modifier)
	if definition.origin == &"environment_meme":
		observed.append(_spawn_external_preset(event_id, definition))
	var remix_created := false
	for index in range(first_variant,variants.size()):
		if variants[index].parent_ids.is_empty(): _assign_event_context(variants[index], country, response)
		var activation := _register_external_world(variants[index], cid)
		if activation.has("error"):
			_restore_lifecycle_state(pristine)
			status = str(activation.error)
			return
		remix_created = remix_created or not variants[index].parent_ids.is_empty()
	event_counts[id] = int(event_counts.get(id, 0)) + 1
	last_event_hours[id] = hour
	var rewards := design_state.unique_event_rewards(definition.design_rewards, events)
	var record := {"instance_id":event_id, "definition_id":id, "title":definition.title, "narrative":definition.narrative, "impact_text":definition.impact_summary(remix_created), "mentor_comment":definition.mentor_comment, "effect_text":definition.title if observed.is_empty() else DeskLocalization.source_join("\n",observed), "origin":str(definition.origin), "hour":hour, "discoveries":Array(definition.discovery_ids), "acknowledged":false, "design_rewards":rewards, "design_source_preset_id":str(definition.external_preset_id), "reward_text":(DeskLocalization.source_join("", ["LOC_EVENT_MATERIALS", _reward_summary(rewards)])) if not rewards.is_empty() else ""}
	record.target_content_snapshot = Lifecycle.revision_snapshot(target) if not target.is_empty() else {}
	record.merge({"country_id":cid, "country_title":title, "category":str(definition.category), "response":response, "response_duration_hours":duration, "applied_effects":applied, "target_variant_id":str(target.get("id", "")), "target_variant_text":str(target.get("text", ""))})
	var response_text := EventResponse.summary(response)
	if not response_text.is_empty(): record.impact_text = response_text
	for effect: MemeDemoEffect in definition.effects:
		if effect.effect_id == &"deviation": record.impact_text = DeskLocalization.source_join(" · ", [record.impact_text, DeskLocalization.source_format("LOC_DEVIATION_DELTA", effect.amount * 100.0)])
	record.narrative = DeskLocalization.source_format(definition.narrative, title, [0]) if "%s" in definition.narrative else definition.narrative
	if record.impact_text.is_empty(): record.impact_text = definition.title
	record.competition_variant_ids = []
	for index in range(first_variant,variants.size()): record.competition_variant_ids.append(str(variants[index].id))
	events.append(record)
	pending_events.append(record)
	if not target.is_empty(): _check_deviation(variant_by_id(_active_variant_id(str(target.id))))

func _event_modifier(event_id: String, definition: MemeDemoEvent, cid: String, duration: float) -> Dictionary:
	return {"source":event_id, "country_id":cid, "variant_ids":[], "effect_id":"response", "amount":0.0, "groups":[], "starts":hour, "expires":hour + duration, "topics":Array(definition.topic_ids), "decay":str(definition.attention_decay), "decay_parameter":maxf(1.0, _event_hours(definition.decay_parameter_hours))}

func _event_country_title(cid: String) -> String:
	for country: MapCountryDefinition in catalog.gameplay_rules.map_settings.countries:
		if str(country.id) == cid: return str(country.short_name_key)
	return cid

func _event_country_contributions() -> Dictionary:
	var population := 0
	var budget := 0
	for row: Dictionary in competition._state.world:
		population += competition._population(str(row.id))
		budget += floori(competition._population(str(row.id)) * catalog.gameplay_rules.attention_fraction)
	var result := {}
	for cid: String in competition._state.countries:
		var country: Dictionary = competition._state.countries[cid]
		var counts := {"adopted":0, "exposed":0, "attention":0}
		for raw: Dictionary in variants:
			if bool(raw.get("retired", false)) or not bool(Lifecycle.content(raw).get("controlled", false)): continue
			for field: String in counts: counts[field] += int(country[field].get(str(raw.id), 0))
		result[cid] = MonitorMetrics.spread(counts, population, budget)
	return result

func _sample_event_country(weights: Dictionary) -> String:
	var total := 0.0
	for weight: float in weights.values(): total += weight
	var cursor := _rng.randf() * total
	for cid: String in weights:
		cursor -= float(weights[cid])
		if cursor < 0.0: return cid
	return str(weights.keys()[-1])

func _event_country(definition: MemeDemoEvent) -> String:
	var contributions := _event_country_contributions()
	var weights := EventScheduler.country_weights(contributions)
	if definition.origin != &"world":
		for cid: String in contributions:
			if float(contributions[cid]) == 0.0: weights.erase(cid)
	if weights.is_empty(): return ""
	return _sample_event_country(weights)

func _event_target(cid: String, definition: MemeDemoEvent = null) -> Dictionary:
	var candidates := _event_candidates(cid, definition, {})
	var total := 0.0
	for item: Dictionary in candidates: total += float(item.weight)
	var cursor := _rng.randf() * total
	for item: Dictionary in candidates:
		cursor -= float(item.weight)
		if cursor < 0.0: return item.variant
	return {}

func _event_candidates(cid: String, definition: MemeDemoEvent, rewrite_cache: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var reacting_groups: Array[String] = []
	var requires_rewrite := false
	if definition != null:
		for effect: MemeDemoEffect in definition.effects:
			requires_rewrite = requires_rewrite or (effect.effect_id == &"remix" and effect.amount > 0.0)
			for id: String in effect.group_ids:
				if id not in reacting_groups: reacting_groups.append(id)
	for variant: Dictionary in competition.active_variants(variants):
		if variant.origin_ids.is_empty() or not competition._state.registry.has(str(variant.id)): continue
		var entry: Dictionary = competition._state.registry[str(variant.id)]
		var weight := float(competition._state.countries[cid].exposed[str(variant.id)])
		if str(entry.origin_country) == cid: weight += 1.0
		if weight <= 0.0: continue
		if not reacting_groups.is_empty():
			var effective: Dictionary = competition.live_profile(str(variant.id))
			var target_groups: Array = effective.get("group_ids", [str(effective.group_id)])
			var matches_group := false
			for id: String in target_groups: matches_group = matches_group or id in reacting_groups
			if not matches_group: continue
		if requires_rewrite:
			if not variant.get("flow_draft") is Dictionary or variant.flow_draft.get("reuse_permission", "unknown") == "restricted": continue
			if not rewrite_cache.has(str(variant.id)):
				var rewrite: Dictionary = EventMutation.candidate(catalog, variant, definition) if not definition.mutation_kind.is_empty() else MutationRules.candidate(catalog, variant, str(definition.id))
				rewrite_cache[str(variant.id)] = not rewrite.is_empty()
			if not rewrite_cache[str(variant.id)]: continue
			if definition.mutation_kind == &"confluence" and _confluence_companion(variant, definition, cid).is_empty(): continue
		candidates.append({"variant":variant, "weight":weight})
	return candidates

func _confluence_companion(parent: Dictionary, definition: MemeDemoEvent, cid: String) -> Dictionary:
	var selected: Dictionary = {}
	var shared_reach := 0.0
	var parent_exposed := float(competition._state.countries[cid].exposed[str(parent.id)])
	for candidate: Dictionary in competition.active_variants(variants):
		if str(candidate.get("meme_id", candidate.id)) == str(parent.get("meme_id", parent.id)) or not competition._state.registry.has(str(candidate.id)): continue
		var relevant := false
		for topic: String in competition.active_topics(candidate.flow_profile): relevant = relevant or topic in definition.mutation_topic_ids
		if not relevant: continue
		var overlap := minf(parent_exposed, float(competition._state.countries[cid].exposed[str(candidate.id)]))
		if overlap > shared_reach:
			selected = candidate
			shared_reach = overlap
	return selected

func _assign_event_context(variant: Dictionary, country: Dictionary, response: Dictionary) -> void:
	var cursor := _rng.randf()
	var cohort: Dictionary = response.cohorts.back()
	for candidate: Dictionary in response.cohorts:
		cursor -= float(candidate.share)
		if cursor < 0.0:
			cohort = candidate
			break
	variant.political_known = true
	variant.political_position = cohort.stance.duplicate()
	variant.pragmatic_position = cohort.pragmatic.duplicate()
	variant.event_reading = {"cohort_id":str(cohort.id), "sentiment":float(cohort.sentiment), "frames":cohort.frames.duplicate()}
	if not cohort.frames.is_empty():
		variant.event_reading.frame = str(cohort.frames[_rng.randi_range(0, cohort.frames.size() - 1)])
		variant.text = DeskLocalization.source_join("\n", [variant.text, variant.event_reading.frame])
	var language := ""
	var language_share := -1.0
	for id: String in country.languages:
		if float(country.languages[id]) > language_share:
			language = id
			language_share = float(country.languages[id])
	variant.language_id = language

func _produce_event_memes() -> void:
	for modifier: Dictionary in modifiers:
		if str(modifier.get("effect_id", "")) != "response" or not modifier.variant_ids.is_empty(): continue
		var response: Dictionary = modifier.response
		var probability := (1.0 + float(response.production)) * EffectRules.decay_weight(modifier, hour) / catalog.gameplay_rules.event_generation_interval_hours
		if _rng.randf() >= probability: continue
		var candidates: Array[MemeDemoEvent] = []
		for definition: MemeDemoEvent in catalog.events:
			if definition.origin == &"environment_meme" and _external_preset_available(str(definition.external_preset_id)): candidates.append(definition)
		if candidates.is_empty(): continue
		var source: MemeDemoEvent = candidates[_rng.randi_range(0, candidates.size() - 1)].duplicate(true)
		source.topic_ids = PackedStringArray(modifier.topics)
		_spawn_external_preset(str(modifier.source), source)
		var variant: Dictionary = variants.back()
		_assign_event_context(variant, catalog.gameplay_rules.country(str(modifier.country_id)), response)
		_register_external_world(variant, str(modifier.country_id))
		for record: Dictionary in events:
			if str(record.instance_id) == str(modifier.source): record.competition_variant_ids.append(str(variant.id))
		for record: Dictionary in pending_events:
			if str(record.instance_id) == str(modifier.source) and str(variant.id) not in record.competition_variant_ids: record.competition_variant_ids.append(str(variant.id))
		if str(active_event.get("instance_id", "")) == str(modifier.source) and str(variant.id) not in active_event.competition_variant_ids: active_event.competition_variant_ids.append(str(variant.id))

func _event_hours(value: float) -> float:
	return value * catalog.gameplay_rules.event_time_scale

func _spawn_remix(event_id: String, creator: String, definition_id: String = "", parent_id: String = "", event_country: String = "", propagation_template: bool = false) -> String:
	var parent := Lifecycle.new(self).active_source(variant_by_id(current_variant_id if parent_id.is_empty() else parent_id))
	var parent_content := Lifecycle.revision_snapshot(parent)
	var event_definition := _event_definition(definition_id)
	var event_mutation := event_definition != null and not event_definition.mutation_kind.is_empty()
	if parent.is_empty():
		return DeskLocalization.source("LOC_NO_DEPLOYED_VERSION_IS_AVAILABLE_TO_REWRITE_151CB474")
	var mutation: Dictionary = {}
	if parent_id.is_empty():
		var origins: Array = parent.origin_ids
		# Newer circulating descendants can become the source of the next community rewrite.
		for index in range(variants.size() - 1, -1, -1):
			var source: Dictionary = variants[index]
			if bool(source.get("retired", false)): continue
			if str(source.get("meme_id", source.id)) != str(parent.get("meme_id", parent.id)): continue
			if source.origin_ids != origins or not competition._state.registry.has(str(source.id)): continue
			if not source.get("flow_draft") is Dictionary or source.flow_draft.get("reuse_permission", "unknown") == "restricted": continue
			parent_content = Lifecycle.revision_snapshot(source)
			mutation = EventMutation.candidate(catalog, parent_content, event_definition) if event_mutation else MutationRules.candidate(catalog, parent_content, definition_id)
			if not mutation.is_empty():
				parent = source
				break
	else:
		if not parent_content.get("flow_draft") is Dictionary: return DeskLocalization.source("LOC_MUTATION_NO_COMPATIBLE_PATCH")
		if parent_content.flow_draft.get("reuse_permission", "unknown") == "restricted":
			return DeskLocalization.source("LOC_REUSE_PERMISSION_IS_RESTRICTED_THIS_RULES_COMPLIANT_23A0C53C")
		if parent_content.patch_ids.size() >= catalog.DESIGN_RULES.module_slots and (not event_mutation or event_definition.mutation_kind != &"expression"):
			return DeskLocalization.source("LOC_MUTATION_PATCHES_FULL")
		mutation = EventMutation.candidate(catalog, parent_content, event_definition) if event_mutation else MutationRules.candidate(catalog, parent_content, definition_id)
	if mutation.is_empty(): return DeskLocalization.source("LOC_MUTATION_NO_COMPATIBLE_PATCH")
	var companion_content := {}
	if event_mutation and event_definition.mutation_kind == &"confluence":
		var cid := event_country if not event_country.is_empty() else str(competition._state.registry[str(parent.id)].origin_country)
		var companion := _confluence_companion(parent, event_definition, cid)
		if companion.is_empty(): return DeskLocalization.source("LOC_MUTATION_NO_COMPATIBLE_PATCH")
		companion_content = Lifecycle.revision_snapshot(companion)
		mutation = EventMutation.merge_with(mutation, companion_content)
	var composed: Dictionary = mutation.composition
	var family_id: String = parent.family_id
	var id := _new_id("variant")
	var source_draft: Dictionary = parent_content.flow_draft
	var reuse_factor := EffectRules.reuse_factor(str(source_draft.reuse_permission),
		PackedStringArray(source_draft.replaceable_slots).size(), find_kernel(parent.kernel_id).required_slots.size(),
		float(source_draft.remix_cost), float(source_draft.context_dependency))
	variants.append({"id":id, "family_id":family_id, "parent_ids":[parent.id], "origin_ids":parent.origin_ids.duplicate(), "creator":creator, "owned":bool(parent_content.owned), "controlled":false, "text":str(composed.expression), "kernel_id":parent.kernel_id, "preset_id":str(parent.get("preset_id", "")), "source_presets":parent.get("source_presets", []).duplicate(true), "semantic_distance":0.0, "language_id":str(source_draft.language_id), "source_event":event_id, "topic_ids":parent.get("topic_ids", []).duplicate(), "reuse_factor":reuse_factor, "patch_ids":mutation.patch_ids.duplicate(), "flow_draft":mutation.flow_draft.duplicate(true)})
	variants.back().mutation_parent_content = parent_content
	if propagation_template: variants.back().propagation_template = {"country_id":event_country, "hour":hour, "adopted":int(competition._state.countries.get(event_country, {}).get("adopted", {}).get(str(parent.id), 0))}
	for field: String in ["meaning", "meaning_id", "language_versions"]: variants.back()[field] = composed[field]
	if event_mutation:
		variants.back().mutation_definition_id = definition_id
		variants.back().mutation_patch_id = str(mutation.patch_id)
		variants.back().topic_ids = Array(mutation.flow_draft.topic_ids)
		variants.back().language_id = str(mutation.flow_draft.language_id)
		if mutation.has("translation_version"): variants.back().translation_version = int(mutation.translation_version)
		if mutation.has("companion_id"):
			variants.back().confluence_source_id = str(mutation.companion_id)
			variants.back().confluence_companion_content = companion_content
	return DeskLocalization.source("LOC_AUDIENCE_REWRITE_FD322DDD")

func _spawn_external_preset(event_id: String, definition: MemeDemoEvent) -> String:
	if not _external_preset_available(str(definition.external_preset_id)): return ""
	var preset := catalog.find_preset(str(definition.external_preset_id))
	if preset == null:
		push_error("External preset not registered: " + str(definition.external_preset_id))
		return DeskLocalization.source("LOC_ERROR_EXTERNAL_PRESET_IS_UNREGISTERED_NO_FAMILY_D2C6C1FB")
	var kernel := find_kernel(str(preset.kernel_id))
	var family_id := _new_id("family")
	var id := _new_id("variant")
	var source_presets: Array = [preset.source_record()]
	var copy := ExpressionText.preset_copy(str(preset.id))
	families[family_id] = {"id":family_id, "owner":"environment", "anchor":preset.family_anchor, "split_threshold":MonitorMetrics.SPLIT_THRESHOLD, "derived_from":[], "preset_id":str(preset.id), "source_presets":source_presets.duplicate(true)}
	variants.append({"id":id, "family_id":family_id, "parent_ids":[], "origin_ids":[], "creator":"environment", "owned":false, "controlled":false, "text":str(copy.expression), "meaning":str(copy.meaning), "kernel_id":str(preset.kernel_id), "preset_id":str(preset.id), "source_presets":source_presets.duplicate(true), "semantic_distance":0.0, "language_id":"seowon", "source_event":event_id, "topic_ids":Array(definition.topic_ids)})
	variants.back().patch_ids = []
	return DeskLocalization.source_format("LOC_S_IS_BEING_CARRIED_ON_BY_OTHERS_36686912", preset.title, [0])

func _open_next_event() -> void:
	if pending_events.is_empty():
		return
	active_event = pending_events.pop_front()
	if phase == "running": resume_speed = speed
	phase = "event"
	speed = 0
	status = DeskLocalization.source("LOC_EVENT_PAUSE_NARRATIVE_AND_ACTUAL_EFFECTS_ARE_C7BD1B68")
	event_raised.emit(active_event.duplicate(true))

func acknowledge_event() -> void:
	if phase != "event" or active_event.is_empty():
		return
	var paper := active_event.duplicate(true)
	paper.acknowledged = true
	for record: Dictionary in event_materials():
		if str(record.instance_id) != str(paper.instance_id) or bool(record.requested): continue
		var errors := design_state.request_event_material(paper, str(record.kind), str(record.id))
		if not errors.is_empty():
			status = DeskLocalization.source_join("；", errors)
			changed.emit()
			return
	var design_errors: PackedStringArray = design_state.claim_event(paper)
	if not design_errors.is_empty():
		status = DeskLocalization.source_join("；",design_errors)
		changed.emit()
		return
	var id: String = active_event.instance_id
	for item: String in active_event.discoveries:
		if item not in discoveries: discoveries.append(item)
	for event in events:
		if event.instance_id == id:
			event.acknowledged = true
			var definition := _event_definition(str(event.definition_id))
			if definition != null and not event.get("design_rewards",[]).is_empty(): event.reward_text = DeskLocalization.source_join("", ["LOC_CLAIMED_9C9021A0", _reward_summary(event.design_rewards)])
	active_event = {}
	phase = "running"
	speed = resume_speed
	_open_next_event()
	if phase == "running" and bool(endgame.war_started): _check_war_extinction()
	changed.emit()

func _start_world_war() -> void:
	var ids: Array = []
	for row: Dictionary in competition._state.world: ids.append(str(row.id))
	endgame = {"war_started":true,"war_started_hour":hour,
		"carrier_country_ids":WorldWar.carrier_countries(variants, competition._state.countries, current_variant_id),
		"collapse_hours":WorldWar.schedule(seed_value, ids, catalog.gameplay_rules.world_war_min_country_hours, catalog.gameplay_rules.world_war_duration_hours)}
	_execute_event(_event_definition("world_war_three"), country_id)
	for record: Dictionary in events:
		if str(record.definition_id) == "world_war_three": record.carrier_country_ids = endgame.carrier_country_ids.duplicate()
	status = DeskLocalization.source("LOC_WAR_ACTIVE_STATUS")
	_open_next_event()

func _advance_world_war() -> void:
	var populations := {}
	var elapsed := hour - int(endgame.war_started_hour)
	for row: Dictionary in competition._state.world:
		var id := str(row.id)
		populations[id] = WorldWar.population(int(row.population), elapsed, int(endgame.collapse_hours[id]))
	competition.apply_populations(populations)
	competition._state.hour = hour
	attention = competition.snapshot(variants, false).attention
	status = DeskLocalization.source("LOC_WAR_ACTIVE_STATUS")
	_check_war_extinction()

func _check_war_extinction() -> void:
	if phase == "complete": return
	var population := 0
	for value: int in competition._state.populations.values(): population += value
	if population == 0:
		_finish({"id":"world_extinction","hour":hour,"war_started_hour":int(endgame.war_started_hour)})
		return
	if endgame.carrier_country_ids.is_empty(): return
	for id: String in endgame.carrier_country_ids:
		if int(competition._state.populations[id]) > 0: return
	_finish({"id":"player_extinction","hour":hour,"war_started_hour":int(endgame.war_started_hour)})

func _finish(result: Dictionary) -> void:
	phase = "complete"
	speed = 0
	status = DeskLocalization.source("LOC_WAR_END_STATUS" if bool(endgame.war_started) else "LOC_INDEPENDENT_RUN_COMPLETE")
	ending = result.duplicate(true)
	completed.emit(snapshot())

func snapshot() -> Dictionary:
	var world: Dictionary = competition.snapshot(variants)
	var state := totals_state(world)
	state.merge({"hour":hour, "run_end_hour":run_end_hour, "phase":phase, "speed":speed, "resume_speed":resume_speed, "country_id":country_id, "country_title":country_title, "status":status, "variants":competition.active_variants(variants).size(), "events":events.duplicate(true), "lineage":competition.active_variants(variants), "discoveries":discoveries.duplicate(), "meme_points":economy.balance, "point_cost":catalog.first_publish_cost if publish_count == 0 else 0, "economy_log":economy.lines(), "attention_budget":attention.budget, "attention_player":attention.player, "attention_external":attention.external, "attention_background":attention.background, "purchase_system":"not_designed"})
	state.propagation_research_ready = propagation_research_ready()
	state.publish_count = publish_count
	state.propagation = competition.propagation_inspection()
	state.meme_candidate_pool = candidate_meme_pool()
	state.current_variant_id = current_variant_id
	state.guide_progress = guidance_progress()
	state.gameplay = {"mode":gameplay_mode(),"day":float(hour)/24.0,"horizon_hours":run_end_hour,"active_seconds":competition._state.active_seconds,"hours_per_active_second":catalog.gameplay_rules.hours_per_active_second}
	state.world_competition = world
	_update_meme_trends(state.world_competition, state.lineage)
	state.meme_trends = _meme_trends.duplicate(true)
	state.world_competition.ending = ending.duplicate(true)
	state.world_competition.endgame = endgame.duplicate(true)
	state.design_state = design_state.snapshot(variants)
	state.design_state.event_materials = event_materials(state.design_state)
	state.event_materials = state.design_state.event_materials.duplicate(true)
	return state

func _update_meme_trends(world: Dictionary, active_variants: Array) -> void:
	var raw_by_id := {}
	for variant: Dictionary in active_variants: raw_by_id[str(variant.id)] = variant
	for row: Dictionary in world.variants:
		var raw: Dictionary = raw_by_id[str(row.id)]
		var initial := MonitorMetrics.initial_variant(variants, raw)
		var sample := {"hour":hour, "spread":float(row.monitor_spread), "deviation":Deviation.total(initial,raw), "deviation_threshold":deviation_threshold(raw)}
		var key := str(row.meme_id)
		if not _meme_trends.has(key): _meme_trends[key] = []
		var history: Array = _meme_trends[key]
		if not history.is_empty() and int(history[-1].hour) >= hour:
			if int(history[-1].hour) > hour: history.clear()
			else: history.pop_back()
		history.append(sample)
		if history.size() > 128: history.pop_front()

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
		parts.append(DeskLocalization.source_format("%s ×%d", [str(design_state.rules.reward_resource(str(reward.kind),str(reward.id)).get("title",reward.id)),int(reward.count)], [0]))
	return DeskLocalization.source_join("、", parts)

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

## 解析与候选账本构造由存档边界完成，失败不改变当前局。
func restore(data: Dictionary) -> PackedStringArray:
	return SaveCodec.new(self).restore(data)

func _capture_lifecycle_state() -> Dictionary:
	var result := {}
	for field: String in ["families", "variants", "deployments", "group_state", "events", "discoveries", "modifiers", "event_counts", "last_event_hours", "pending_events", "active_event", "attention", "current_variant_id", "draft_distance", "publish_count", "_serial", "_event_clock_arrivals", "phase", "speed", "resume_speed", "status", "latest_draft", "ending"]:
		var value: Variant = get(field)
		result[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	result.competition = competition._state.duplicate(true)
	result.monitor_previous = competition._monitor_previous_scores.duplicate(true)
	result.design = design_state.payload()
	result.economy = economy.payload()
	result.rng_state = _rng.state
	return result

func _restore_lifecycle_state(pristine: Dictionary) -> void:
	for field: String in pristine:
		if field not in ["competition", "monitor_previous", "design", "economy", "rng_state"]: set(field, pristine[field])
	competition._state = pristine.competition.duplicate(true)
	competition._monitor_previous_scores = pristine.monitor_previous.duplicate(true)
	competition._fitness_cache.clear()
	design_state._state = pristine.design.duplicate(true)
	economy.restore(pristine.economy)
	_rng.state = pristine.rng_state

func _active_variant_id(id: String) -> String:
	var raw := variant_by_id(id)
	return str(Lifecycle.new(self).active_source(raw).id) if not raw.is_empty() else id

func _runtime_modifiers() -> Array[Dictionary]:
	var current := {}
	for raw: Dictionary in variants:
		if not bool(raw.get("retired", false)): current[str(raw.get("meme_id", raw.id))] = str(raw.id)
	var meme_by_revision := {}
	for raw: Dictionary in variants: meme_by_revision[str(raw.id)] = str(raw.get("meme_id", raw.id))
	var result: Array[Dictionary] = []
	for original: Dictionary in modifiers:
		var modifier := original.duplicate(true)
		var ids: Array = []
		for id: String in original.variant_ids:
			var active := str(current.get(str(meme_by_revision.get(id, id)), id))
			if active not in ids: ids.append(active)
		modifier.variant_ids = ids
		result.append(modifier)
	return result
