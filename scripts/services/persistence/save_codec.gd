extends RefCounted

const MonitorMetrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const MemeLifecycle = preload("res://scripts/gameplay/competition/meme_lifecycle.gd")
## 当前存档格式的唯一边界：先解析和验证，再一次性安装完整候选状态。

const CompetitionState = preload("res://scripts/gameplay/competition/competition_state.gd")
const PropagationRewards = preload("res://scripts/gameplay/economy/propagation_rewards.gd")
const DesignState = preload("res://scripts/gameplay/design/design_state.gd")
const MutationRules = preload("res://scripts/gameplay/events/mutation_rules.gd")
const EventMutation = preload("res://scripts/gameplay/events/event_mutation.gd")
const EventResponse = preload("res://scripts/gameplay/events/event_response.gd")
const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")
const WorldWar = preload("res://scripts/gameplay/events/world_war.gd")
const SAVE_VERSION := 3
const LEGACY_PACE_CONTENT := "1eb370766ef2cd523c50a6e4de1f5fbbe7d02e01a3f3eb39dc576223dd2082d5"
const LEGACY_PACE_POLICY := "57221cb7cc0276c879fb79dd37867303c5cf75aed38284ba111aefda425a73fe"

var simulation: RefCounted
var catalog: MemeDemoCatalog
var competition: RefCounted
var design_state: MemeDemoDesignState
var economy: MemeDemoEconomy
var _author_configurations: Dictionary = {}

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
	data.ending = simulation.ending.duplicate(true)
	data.endgame = simulation.endgame.duplicate(true)
	data.design_state = design_state.payload()
	data.guide_progress = simulation.guidance_progress()
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
	_author_configurations.clear()
	var decoded := _decode_precision(data, errors)
	if not errors.is_empty(): return {}
	_upgrade_pace_signatures(decoded)
	# Guidance progress is optional in version-3 saves.
	if not decoded.has("guide_progress"): decoded.guide_progress = {}
	errors.append_array(_validate_current(decoded))
	if not errors.is_empty(): return {}
	return decoded

func _upgrade_pace_signatures(data: Dictionary) -> void:
	if data.get("content_version") != 14 or data.get("content_signature") != LEGACY_PACE_CONTENT or not data.get("competition_state") is Dictionary: return
	if data.competition_state.get("policy_signature") != LEGACY_PACE_POLICY: return
	# Rebuild the old signatures so unrelated content changes still invalidate the save.
	var legacy_catalog: Dictionary = _resource_data(catalog)
	for field: String in ["adoption_response", "exposure_response"]: legacy_catalog.gameplay_rules[field] = 0.0015
	legacy_catalog.gameplay_rules.attention_activation = 4.0
	var legacy_content := JSON.stringify({"catalog":legacy_catalog,"rewards":PropagationRewards.signature(),"propagation_content":FileAccess.get_file_as_string("res://data/propagation/content_profiles.json").sha256_text()}, "", true, true).sha256_text()
	var legacy_policy: Dictionary = legacy_catalog.gameplay_rules.duplicate(true)
	legacy_policy.erase("map_settings")
	if legacy_content != LEGACY_PACE_CONTENT or JSON.stringify(legacy_policy, "", true, true).sha256_text() != LEGACY_PACE_POLICY: return
	data.content_signature = content_signature()
	data.competition_state.policy_signature = catalog.gameplay_rules.signature()

## 空草稿合法；出现草稿时，首发前后都遵守相同字段和有限值约束。
func _draft_from_json(draft: Dictionary, errors: PackedStringArray) -> Dictionary:
	if draft.is_empty(): return {}
	var decoded := draft.duplicate(true)
	for key in ["political_position", "pragmatic_position"]:
		var point: Variant = draft.get(key)
		if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]):
			errors.append(DeskLocalization.source("LOC_SAVED_DRAFT_COORDINATES_MUST_CONTAIN_TWO_FINITE_6899D7DB") + key)
		else: decoded[key] = Vector2(point[0], point[1])
	if not draft.get("slots") is Dictionary or not draft.get("topic_ids") is Array or not draft.get("replaceable_slots") is Array or not draft.get("political_known") is bool:
		errors.append(DeskLocalization.source("LOC_A_SAVED_DRAFT_FIELD_HAS_THE_WRONG_E73A9EFF"))
	for key in ["kernel_id", "preset_id", "channel_id", "group_id", "language_id", "target", "reuse_permission"]:
		if not (draft.get(key) is String or draft.get(key) is StringName): errors.append(DeskLocalization.source("LOC_INVALID_SAVED_DRAFT_TEXT_TYPE_A0FF1018") + key)
		else: decoded[key] = str(draft[key])
	for key in ["remix_cost", "context_dependency", "language_access", "recognizability"]:
		if not _number(draft.get(key)): errors.append(DeskLocalization.source("LOC_INVALID_SAVED_DRAFT_NUMERIC_TYPE_3B317995") + key)
	for key in ["topic_ids", "replaceable_slots"]:
		if not draft.get(key) is Array: continue
		for value: Variant in draft[key]:
			if not value is String: errors.append(DeskLocalization.source("LOC_SAVED_DRAFT_LISTS_MAY_ONLY_CONTAIN_TEXT_3474D194") + key)
	if draft.get("slots") is Dictionary:
		for key: Variant in draft.slots:
			if not key is String or not draft.slots[key] is String: errors.append(DeskLocalization.source("LOC_SAVED_SEMANTIC_SLOTS_MUST_USE_STRING_KEYS_46CCFD3C"))
	if not errors.is_empty(): return {}
	decoded.topic_ids = PackedStringArray(draft.topic_ids)
	decoded.replaceable_slots = PackedStringArray(draft.replaceable_slots)
	return decoded

func _validate_current(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if data.get("save_version") != SAVE_VERSION or not _integer(data.get("content_version")) or int(data.content_version) != catalog.content_version or data.get("content_signature") != content_signature() or data.get("gameplay_mode") != "world_competition":
		return PackedStringArray([DeskLocalization.source("LOC_THE_SAVE_VERSION_CONTENT_OR_GAMEPLAY_FORMAT_7D8AC708")])
	var numeric := ["seed", "hour", "run_end_hour", "speed", "resume_speed", "draft_distance", "publish_count", "serial"]
	var strings := ["rng_state", "phase", "country_id", "country_title", "status", "current_variant_id"]
	var dictionaries := ["latest_draft", "families", "group_state", "event_counts", "last_event_hours", "active_event", "attention", "economy", "design_state", "competition_state", "ending", "endgame"]
	var arrays := ["variants", "deployments", "events", "discoveries", "modifiers", "pending_events"]
	for key in numeric:
		if not data.has(key) or not _number(data[key]): errors.append(DeskLocalization.source("LOC_WRONG_NUMERIC_TYPE_IN_SAVE_8A2D94B8") + key)
	for key in strings:
		if not data.get(key) is String: errors.append(DeskLocalization.source("LOC_WRONG_TEXT_TYPE_IN_SAVE_2227F90E") + key)
	for key in dictionaries:
		if not data.get(key) is Dictionary: errors.append(DeskLocalization.source("LOC_WRONG_OBJECT_TYPE_IN_SAVE_8B841260") + key)
	for key in arrays:
		if not data.get(key) is Array: errors.append(DeskLocalization.source("LOC_WRONG_ARRAY_TYPE_IN_SAVE_8EB741D8") + key)
	if not errors.is_empty(): return errors
	for key in ["seed", "hour", "run_end_hour", "speed", "resume_speed", "publish_count", "serial"]:
		if not _integer(data[key]): errors.append(DeskLocalization.source("LOC_INVALID_SAVED_INTEGER_25F32879") + key)
	if not str(data.rng_state).is_valid_int() or data.phase not in ["draft", "running", "event", "complete"] or data.hour < 0 or data.hour > data.run_end_hour or data.run_end_hour != catalog.run_hours or data.speed < 0 or data.speed > 2 or data.resume_speed < 0 or data.resume_speed > 2 or data.publish_count < 0 or data.serial < 0 or data.draft_distance < 0 or data.draft_distance > 1:
		errors.append(DeskLocalization.source("LOC_THE_SAVED_PHASE_RANDOM_STATE_COUNT_OR_244F19E2"))
	if not errors.is_empty(): return errors
	errors.append_array(competition.validate_payload(data.competition_state, data.variants, int(data.hour)))
	if data.phase in ["event", "draft", "complete"] and data.speed != 0:
		errors.append(DeskLocalization.source("LOC_NON_RUNNING_PHASES_MUST_BE_PAUSED_03C4597B"))
	errors.append_array(economy.validate_payload(data.economy))
	errors.append_array(PropagationRewards.validate_ledger(data.economy.get("transactions", [])))
	if competition._canonical(data.competition_state.get("propagation", {}).get("live_skill_ids", [])) != competition._canonical(data.design_state.get("unlocked_skills", [])): errors.append("Live propagation research differs from the author unlock ledger")
	for key in ["variants", "deployments", "events", "modifiers", "pending_events"]:
		for entry in data[key]:
			if not entry is Dictionary: errors.append(DeskLocalization.source("LOC_WRONG_SAVED_RECORD_TYPE_879E5C19") + key)
	for item in data.discoveries:
		if not item is String: errors.append(DeskLocalization.source("LOC_WRONG_SAVED_DISCOVERY_TYPE_C3CA7454"))
	if not errors.is_empty(): return errors
	for key in ["events", "pending_events"]:
		for event in data[key]:
			_validate_event_copy(event, errors)
	if not data.active_event.is_empty(): _validate_event_copy(data.active_event, errors)
	if errors.is_empty(): _validate_event_history(data, errors)
	for deployment in data.deployments:
		if not deployment.has_all(["id", "variant_id", "country_id", "group_id", "channel_id", "hour"]): errors.append(DeskLocalization.source("LOC_INVALID_SAVED_DEPLOYMENT_RECORD_FIELDS_5ADCB11F"))
	if not errors.is_empty(): return errors
	var variant_ids: Dictionary = {}
	var variant_order := {}
	# 先确认来源字段类型，再比较谱系关系。
	for family in data.families.values():
		if family is Dictionary: _validate_preset_sources(family, DeskLocalization.source("LOC_FAMILY_3C659F55"), errors)
	for variant in data.variants:
		_validate_preset_sources(variant, DeskLocalization.source("LOC_VERSION_5F76B2BF"), errors)
	if not errors.is_empty(): return errors
	for family in data.families.values():
		if not family is Dictionary or not family.has_all(["id", "owner", "anchor", "split_threshold", "derived_from"]) or not _number(family.get("split_threshold")) or not family.get("derived_from") is Array:
			errors.append(DeskLocalization.source("LOC_INVALID_SAVED_FAMILY_FIELDS_0773D71C"))
			continue
		var family_preset := catalog.find_preset(str(family.get("preset_id", "")))
		if family_preset != null and family.derived_from.is_empty() and str(family.anchor) != family_preset.family_anchor:
			errors.append(DeskLocalization.source("LOC_SAVED_PRESET_FAMILY_ANCHOR_MISMATCH_D5D6F4D8"))
		for previous in family.derived_from:
			if not data.families.has(previous) or not data.families[previous] is Dictionary:
				errors.append(DeskLocalization.source("LOC_SAVED_DERIVED_FAMILY_SOURCE_IS_MISSING_41B5B7C4"))
			elif family.get("source_presets", []) != data.families[previous].get("source_presets", []) or str(family.get("preset_id", "")) != str(data.families[previous].get("preset_id", "")):
				errors.append(DeskLocalization.source("LOC_SAVED_FAMILY_SPLIT_DID_NOT_RETAIN_THE_83F8D7DB"))
	for variant in data.variants:
		if not variant.has_all(["id", "family_id", "parent_ids", "origin_ids", "creator", "owned", "controlled", "text", "kernel_id", "semantic_distance", "language_id"]) or not variant.parent_ids is Array or not variant.origin_ids is Array:
			errors.append(DeskLocalization.source("LOC_INVALID_SAVED_VERSION_FIELDS_4AC19955"))
			continue
		if variant_ids.has(variant.id) or not data.families.has(variant.family_id): errors.append(DeskLocalization.source("LOC_INVALID_SAVED_VERSION_IDENTITY_OR_FAMILY_REFERENCE_7061AAAB"))
		variant_order[variant.id] = variant_ids.size()
		variant_ids[variant.id] = variant
		var variant_preset := catalog.find_preset(str(variant.get("preset_id", "")))
		if variant_preset != null and str(variant.kernel_id) != str(variant_preset.kernel_id): errors.append(DeskLocalization.source("LOC_SAVED_VERSION_PRESET_DOES_NOT_MATCH_ITS_B085B9F8"))
		if data.families.get(variant.family_id) is Dictionary:
			var family: Dictionary = data.families[variant.family_id]
			if variant.get("source_presets", []) != family.get("source_presets", []) or str(variant.get("preset_id", "")) != str(family.get("preset_id", "")):
				errors.append(DeskLocalization.source("LOC_SAVED_VERSION_AND_FAMILY_HAVE_INCONSISTENT_CASE_E3CA2999"))
	if not str(data.current_variant_id).is_empty() and not variant_ids.has(data.current_variant_id): errors.append(DeskLocalization.source("LOC_CURRENT_SAVED_VERSION_IS_MISSING_EA4E2869"))
	if not errors.is_empty(): return errors
	errors.append_array(design_state.validate_payload(data.design_state, data.events, data.variants, data.economy))
	if not errors.is_empty(): return errors
	for variant in data.variants:
		for parent in variant.get("parent_ids", []):
			if not variant_ids.has(parent):
				errors.append(DeskLocalization.source("LOC_SAVED_SOURCE_VERSION_IS_MISSING_385BFC5A"))
			elif int(variant_order[parent]) >= int(variant_order[variant.id]):
				errors.append(DeskLocalization.source("LOC_COMPETITION_VERSIONS_MAY_REFERENCE_ONLY_PREVIOUSLY_EXISTING_8B80AED8"))
			elif variant.get("source_presets", []) != variant_ids[parent].get("source_presets", []) or str(variant.get("preset_id", "")) != str(variant_ids[parent].get("preset_id", "")):
				errors.append(DeskLocalization.source("LOC_SAVED_DERIVED_VERSION_DID_NOT_RETAIN_ITS_605360FB"))
		if variant.has("confluence_source_id"):
			var companion_id := str(variant.confluence_source_id)
			if not variant_ids.has(companion_id) or int(variant_order.get(companion_id, variant_order[variant.id])) >= int(variant_order[variant.id]): errors.append("Confluence can reference only an earlier circulating meme")
		for origin in variant.get("origin_ids", []):
			if not variant_ids.has(origin): errors.append(DeskLocalization.source("LOC_SAVED_ORIGINAL_VERSION_SOURCE_IS_MISSING_84500A57"))
			elif (not variant_ids[origin].parent_ids.is_empty() or str(variant_ids[origin].creator) != "player"): errors.append(DeskLocalization.source("LOC_A_COMPETITION_LINEAGE_MUST_ORIGINATE_FROM_THE_76CFFF89"))
	if errors.is_empty(): errors.append_array(_validate_lifecycle_field_types(data.variants))
	if errors.is_empty(): errors.append_array(_validate_content_snapshots(data, variant_ids))
	if errors.is_empty(): errors.append_array(_validate_variant_compositions(data.variants, variant_ids))
	if errors.is_empty(): errors.append_array(_validate_meme_lifecycle(data, variant_ids))
	if errors.is_empty():
		var source_checker: RefCounted = CompetitionState.new(catalog)
		source_checker._state = data.competition_state.duplicate(true)
		if competition._canonical(data.attention) != competition._canonical(source_checker.snapshot(data.variants,false).attention): errors.append(DeskLocalization.source("LOC_DISPLAYED_ATTENTION_DOES_NOT_MATCH_ACTUAL_COUNTRY_A023EA74"))
		for variant: Dictionary in data.variants:
			if not variant.get("owned") is bool or not variant.get("controlled") is bool:
				errors.append(DeskLocalization.source("LOC_COMPETITION_OWNERSHIP_AND_CONTROL_MUST_EACH_BE_61837AA4"))
				continue
			if str(variant.creator) == "player" and (not variant.owned or not variant.controlled): errors.append(DeskLocalization.source("LOC_THE_PLAYER_S_ORIGINAL_VERSION_CANNOT_IMPERSONATE_118E38C2"))
			if str(variant.creator) != "player" and variant.controlled: errors.append(DeskLocalization.source("LOC_AN_EXTERNAL_VERSION_CANNOT_CLAIM_PLAYER_CONTROL_0B60A355"))
			var family: Dictionary = data.families[variant.family_id]
			if (not variant.has("meme_id") or bool(variant.get("legacy_identity", false))) and (not family.owner is String or variant.owned != (str(family.owner) == "player")): errors.append(DeskLocalization.source("LOC_AUTHOR_OWNERSHIP_DOES_NOT_MATCH_THE_ACTUAL_4ADFAFF9"))
			if not _number(variant.semantic_distance) or float(variant.semantic_distance) < 0.0 or float(variant.semantic_distance) > 1.0: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_SEMANTIC_DRIFT_8C39ABE4"))
			if str(variant.creator) != "player":
				if variant.parent_ids.is_empty():
					if not variant.origin_ids.is_empty() or variant.owned: errors.append(DeskLocalization.source("LOC_AN_INDEPENDENT_EXTERNAL_VERSION_CANNOT_CLAIM_PLAYER_CB14A8E0"))
				else:
					var parent: Dictionary = variant_ids[variant.parent_ids[0]]
					if competition._canonical(variant.origin_ids) != competition._canonical(parent.origin_ids): errors.append(DeskLocalization.source("LOC_MUTATIONS_MUST_RETAIN_THE_ACTUAL_ORIGINAL_DEPLOYMENT_DD642E47"))
					var split: bool = MonitorMetrics.should_split(float(variant.semantic_distance))
					if (not variant.has("meme_id") or bool(variant.get("legacy_identity", false))) and (split != (str(variant.family_id) != str(parent.family_id)) or bool(variant.owned) != (bool(parent.owned) and not split)): errors.append(DeskLocalization.source("LOC_MUTATION_OWNERSHIP_CONFLICTS_WITH_THE_FIXED_FAMILY_6809C659"))
			var entry: Dictionary = data.competition_state.registry[str(variant.id)]
			if not variant.get("flow_profile") is Dictionary or competition._canonical(variant.flow_profile) != competition._canonical(entry.profile): errors.append(DeskLocalization.source("LOC_COMPETITION_EXPRESSION_CONFIGURATION_DOES_NOT_MATCH_ITS_FCCA1944"))
			if variant.controlled:
				if not variant.get("flow_draft") is Dictionary:
					errors.append(DeskLocalization.source("LOC_AUTHOR_TRANSMISSION_CONFIGURATION_LACKS_ITS_ORIGINAL_DRAFT_ACD1228C"))
					continue
				var flow_draft: Dictionary = variant.flow_draft
				if not flow_draft.get("slots") is Dictionary or not flow_draft.get("flow_skill_ids") is Array:
					errors.append(DeskLocalization.source("LOC_INVALID_AUTHOR_TRANSMISSION_DRAFT_STRUCTURE_0E4B1BED"))
					continue
				var flow_errors := PackedStringArray()
				var flow_input := _draft_from_json(flow_draft, flow_errors)
				if not flow_errors.is_empty():
					errors.append_array(flow_errors)
					continue
				errors.append_array(simulation.validate_draft(flow_input))
				for skill_id: Variant in flow_draft.flow_skill_ids:
					if skill_id not in data.get("design_state",{}).get("unlocked_skills",[]): errors.append(DeskLocalization.source("LOC_SPREAD_ABILITY_LACKS_A_VALID_UNLOCK_RECORD_237BB394"))
				if competition._canonical(competition.profile(flow_draft)) != competition._canonical(entry.profile) or not design_state.author_marks_valid(flow_draft,data.design_state): errors.append(DeskLocalization.source("LOC_TRANSMISSION_CONFIGURATION_DOES_NOT_MATCH_AUTHOR_ACTIONS_3FEFBD17"))
				if str(flow_draft.get("kernel_id","")) != str(variant.kernel_id) or str(flow_draft.get("preset_id","")) != str(variant.get("preset_id","")): errors.append(DeskLocalization.source("LOC_TRANSMISSION_CONFIGURATION_CANNOT_REPLACE_THE_BASE_FORM_EA8990C3"))
			else:
				var parent_id: String = str(variant.parent_ids[0]) if not variant.parent_ids.is_empty() else ""
				var profile_version := int(variant.get("mutation_policy", {}).get("profile_version", 1))
				if competition._canonical(source_checker.inherited_profile(variant,parent_id,profile_version)) != competition._canonical(entry.profile): errors.append(DeskLocalization.source("LOC_EXTERNAL_TRANSMISSION_EXPRESSION_DOES_NOT_MATCH_ITS_121705CA"))
			if str(variant.get("source_event","")) != "":
				var found := false
				for event: Dictionary in data.events:
					if str(event.instance_id) == str(variant.source_event) and str(variant.id) in event.get("competition_variant_ids",[]): found = true
				if not found: errors.append(DeskLocalization.source("LOC_COMPETITION_EMERGENCE_EVENT_SOURCE_IS_MISSING_98B83A6B"))
		for event: Dictionary in data.events:
			if str(event.origin) == "transmission":
				var target_id := str(event.get("target_variant_id", ""))
				if not variant_ids.has(target_id) or variant_ids[target_id].origin_ids.is_empty():
					errors.append("Transmission events require a player lineage target")
				elif event.response.topic_ids != event.get("target_content_snapshot", variant_ids[target_id]).get("topic_ids", []) or event.target_variant_text != event.get("target_content_snapshot", variant_ids[target_id]).get("text", ""):
					errors.append("Transmission response must match its recorded target")
			for id in event.get("competition_variant_ids",[]):
				if not variant_ids.has(id) or str(variant_ids[id].get("source_event","")) != str(event.instance_id): errors.append(DeskLocalization.source("LOC_INVALID_EVENT_COMPETITION_VERSION_REFERENCE_D6AAF201"))
				elif variant_ids[id].parent_ids.is_empty(): _validate_event_reading(variant_ids[id], event, data.competition_state, errors)
				elif str(variant_ids[id].get("mutation_definition_id", "")) != str(event.definition_id): errors.append("Event rewrites must retain their mutation definition")
	var restored_draft := _draft_from_json(data.latest_draft, errors)
	if data.publish_count > 0 and restored_draft.is_empty(): errors.append(DeskLocalization.source("LOC_THE_PUBLISHED_SAVE_HAS_NO_CURRENT_DRAFT_D36B7865"))
	if not restored_draft.is_empty() and errors.is_empty(): errors.append_array(simulation.validate_draft(restored_draft))
	if variant_ids.has(data.current_variant_id) and restored_draft.get("preset_id", "") != variant_ids[data.current_variant_id].get("preset_id", ""):
		errors.append(DeskLocalization.source("LOC_CURRENT_SAVED_DRAFT_DOES_NOT_MATCH_THE_8DDF6CAD"))
	for group in catalog.groups:
		var id := str(group.id)
		if not data.group_state.has(id) or not data.group_state[id] is Dictionary or not data.group_state[id].has_all(["exposed", "owned", "external", "fatigue", "trust"]):
			errors.append(DeskLocalization.source("LOC_SAVE_IS_MISSING_AUDIENCE_5FBDC01C") + id)
			continue
		var state: Dictionary = data.group_state[id]
		var valid := true
		for key in ["exposed", "owned", "external", "fatigue", "trust"]:
			valid = valid and _number(state[key])
		if not valid:
			errors.append(DeskLocalization.source("LOC_INVALID_SAVED_AUDIENCE_NUMERIC_VALUES_34F8BFA2"))
			continue
		if state.exposed < 0 or state.exposed > group.sample_size or state.owned < 0 or state.external < 0 or state.owned + state.external > state.exposed + 0.001 or state.fatigue < 0 or state.fatigue > 1 or state.trust < 0 or state.trust > 1:
			errors.append(DeskLocalization.source("LOC_SAVED_POPULATION_STATE_IS_NOT_CONSERVED_1B6C89E6"))
	if not data.attention.has_all(["budget", "player", "external", "background"]):
		errors.append(DeskLocalization.source("LOC_SAVE_LACKS_AN_ATTENTION_BUDGET_B68A9938"))
	else:
		var valid := true
		for key in ["budget", "player", "external", "background"]:
			valid = valid and _number(data.attention[key]) and data.attention[key] >= 0
		if not valid or data.attention.player + data.attention.external + data.attention.background != data.attention.budget: errors.append(DeskLocalization.source("LOC_SAVED_ATTENTION_IS_NOT_CONSERVED_1243FF3C"))
	if data.phase == "event" and (data.active_event.is_empty() or not data.active_event.has_all(["instance_id", "discoveries", "title", "narrative", "effect_text"])):
		errors.append(DeskLocalization.source("LOC_EVENT_PAUSE_LACKS_A_CURRENT_EVENT_A9409913"))
	for modifier: Dictionary in data.modifiers:
		if not modifier.get("source") is String or not _number(modifier.get("amount")) or not _number(modifier.get("expires")) or not _integer(modifier.get("starts")) or not _number(modifier.get("decay_parameter")) or modifier.get("decay") not in ["constant", "linear", "exponential", "periodic"] or not modifier.get("groups") is Array or not modifier.get("topics") is Array:
			errors.append(DeskLocalization.source("LOC_A_SAVED_EFFECT_RECORD_HAS_AN_INVALID_B9CEC168"))
			continue
		for key in ["groups", "topics"]:
			for identity: Variant in modifier[key]:
				if not identity is String: errors.append(DeskLocalization.source("LOC_SAVED_EFFECT_TARGETS_MUST_BE_STRING_IDENTIFIERS_DD145605"))
		if modifier.has("country_id"):
			var source: Dictionary = {}
			for record: Dictionary in data.events:
				if record.instance_id == modifier.source: source = record
			if source.is_empty() or modifier.country_id != source.country_id or not modifier.get("variant_ids") is Array or not modifier.get("effect_id") is String:
				errors.append("Scoped effects require their recorded event country and target")
			elif str(modifier.effect_id) == "response" and competition._canonical(modifier.get("response")) != competition._canonical(source.response):
				errors.append("Scoped effects cannot replace their resolved country response")
			elif not source.is_empty():
				_validate_scoped_modifier(modifier, source, errors)
	for value in data.event_counts.values():
		if not _number(value) or value < 0: errors.append(DeskLocalization.source("LOC_INVALID_SAVED_EVENT_COUNT_2C1B6BFB"))
	for value in data.last_event_hours.values():
		if not _number(value): errors.append(DeskLocalization.source("LOC_INVALID_SAVED_EVENT_TIME_61D60A84"))
	if errors.is_empty() and not design_state.author_marks_valid(data.latest_draft, data.design_state): errors.append(DeskLocalization.source("LOC_CURRENT_DRAFT_EXPRESSION_PATCH_OR_ABILITY_PROVENANCE_F36FC5F9"))
	if errors.is_empty(): errors.append_array(_validate_guidance_progress(data))
	if errors.is_empty(): errors.append_array(_validate_endgame(data))
	if errors.is_empty(): data.latest_draft = restored_draft
	return errors

func _validate_scoped_modifier(modifier: Dictionary, source: Dictionary, errors: PackedStringArray) -> void:
	var definition: MemeDemoEvent = simulation._event_definition(str(source.definition_id))
	var expected: Dictionary = simulation._event_modifier(str(source.instance_id), definition, str(source.country_id), float(source.response_duration_hours))
	expected.starts = int(source.hour)
	expected.expires = float(source.hour) + float(source.response_duration_hours)
	if str(modifier.effect_id) == "response":
		expected.response = source.response
		if str(source.origin) == "transmission":
			expected.variant_ids = [str(source.target_variant_id)]
			expected.topics = []
		if competition._canonical(expected) != competition._canonical(modifier): errors.append("Country response scope or lifetime differs from its event")
		return
	for effect: Dictionary in source.applied_effects:
		if str(effect.effect_id) in ["adoption", "remix"]: continue
		var candidate := expected.duplicate(true)
		candidate.effect_id = str(effect.effect_id)
		candidate.amount = -float(effect.amount) if effect.effect_id == "fatigue" else float(effect.amount)
		candidate.groups = effect.group_ids.duplicate()
		candidate.variant_ids = [str(source.target_variant_id)]
		candidate.topics = []
		candidate.expires = float(source.hour) + float(effect.duration_hours)
		if competition._canonical(candidate) == competition._canonical(modifier): return
	errors.append("Scoped effect differs from its recorded event outcome")

func _validate_event_reading(variant: Dictionary, event: Dictionary, world: Dictionary, errors: PackedStringArray) -> void:
	var reading: Dictionary = variant.get("event_reading", {})
	var matched := false
	for cohort: Dictionary in event.response.cohorts:
		if str(cohort.id) != str(reading.get("cohort_id", "")): continue
		matched = true
		if float(cohort.share) <= 0.0 or reading.get("sentiment") != cohort.sentiment or reading.get("frames") != cohort.frames or variant.get("political_position") != cohort.stance or variant.get("pragmatic_position") != cohort.pragmatic or not bool(variant.get("political_known", false)):
			errors.append("Independent event memes must preserve their actual country interpretation")
		if not cohort.frames.is_empty() and str(reading.get("frame", "")) not in cohort.frames: errors.append("Event expression frame is not in the reacting cohort")
	if not matched: errors.append("Independent event memes require a country audience")
	if str(world.registry[str(variant.id)].origin_country) != str(event.country_id): errors.append("Event meme origin differs from its country")

func _mutation_threshold(variant: Dictionary, parent: Dictionary, _variants_by_id: Dictionary, data: Dictionary, errors: PackedStringArray) -> float:
	var base: float = MonitorMetrics.SPLIT_THRESHOLD
	if not variant.has("mutation_policy"):
		if variant.has("propagation_template"): errors.append("Community templates require their historical propagation policy")
		return base
	var policy: Variant = variant.mutation_policy
	if not policy is Dictionary or policy.get("schema") != 1 or not policy.get("skill_ids") is Array or not _number(policy.get("threshold")) or not _integer(policy.get("hour")) or not _integer(policy.get("ledger_size")) or str(policy.get("source_id", "")) != str(parent.id):
		errors.append("Community propagation policy requires its actual source, research ledger and finite threshold")
		return base
	var metric_version: Variant = policy.get("metric_version", 1)
	if not _integer(metric_version) or int(metric_version) not in [1, MonitorMetrics.DEVIATION_VERSION]:
		errors.append("Community propagation policy has an unknown deviation metric")
		return base
	var profile_version: Variant = policy.get("profile_version", 1)
	if not _integer(profile_version) or int(profile_version) not in [1, CompetitionState.INHERITED_PROFILE_VERSION]:
		errors.append("Community propagation policy has an unknown profile version")
		return base
	var ledger_size := int(policy.ledger_size)
	if int(policy.hour) < 0 or int(policy.hour) > int(data.hour) or ledger_size < 0 or ledger_size > data.economy.transactions.size():
		errors.append("Community propagation policy clock or ledger boundary is invalid")
		return base
	var expected_skills: Array = []
	var lineage: bool = str(parent.get("creator", "")) == "player" or not parent.get("origin_ids", []).is_empty()
	if lineage:
		for transaction: Dictionary in data.economy.transactions.slice(0, ledger_size):
			if int(transaction.hour) > int(policy.hour): errors.append("Propagation policy cannot use a future research transaction")
			if transaction.has("propagation_skill_id"):
				var skill := str(transaction.propagation_skill_id)
				if skill in expected_skills or skill not in data.design_state.unlocked_skills: errors.append("Propagation policy research provenance is invalid")
				expected_skills.append(skill)
	if competition._canonical(policy.skill_ids) != competition._canonical(expected_skills): errors.append("Community propagation skills differ from the recorded research at birth")
	var historical_parent: Dictionary = variant.get("mutation_parent_content", parent).duplicate(true)
	var historical_profile: Dictionary = historical_parent.get("flow_profile", {}).duplicate(true)
	historical_profile.skill_ids = policy.skill_ids.duplicate()
	historical_parent.flow_profile = historical_profile
	var expected: float = competition.propagation_rules.split_threshold(base, historical_parent, {"flow_draft":variant.get("flow_draft", {})})
	if not is_equal_approx(float(policy.threshold), expected): errors.append("Community propagation threshold provenance is invalid")
	if variant.has("propagation_template"):
		var record: Variant = variant.propagation_template
		if not record is Dictionary or not record.get("country_id") is String or not _integer(record.get("hour")) or not _integer(record.get("adopted")):
			errors.append("Community template source requires its country, time and observed adoption")
		elif not competition.has_country(str(record.country_id)) or int(record.hour) != int(policy.hour) or int(record.adopted) <= 0 or int(record.adopted) > int(catalog.gameplay_rules.country(str(record.country_id)).get("population", 0)):
			errors.append("Community template source country, time or adoption is invalid")
		if "public_template" not in policy.skill_ids or not competition.propagation_rules.can_template(historical_profile): errors.append("Community template publication provenance is invalid")
	return expected


func _validate_variant_compositions(variants: Array, variants_by_id: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for variant: Dictionary in variants:
		if not variant.get("patch_ids") is Array:
			return PackedStringArray(["Saved versions require expression patch IDs"])
		for id: Variant in variant.patch_ids:
			if not id is String: return PackedStringArray(["Expression patch IDs must be strings"])
		errors.append_array(catalog.DESIGN_RULES.patch_errors(str(variant.preset_id), variant.patch_ids))
		if not errors.is_empty(): return errors
		if str(variant.creator) != "player" and variant.parent_ids.is_empty():
			var preset: MemeDemoPreset = catalog.find_preset(str(variant.preset_id))
			var expected_expression := str(ExpressionText.preset_copy(str(variant.preset_id)).get("expression", ""))
			if variant.get("event_reading", {}).has("frame"): expected_expression = DeskLocalization.source_join("\n", [expected_expression, str(variant.event_reading.frame)])
			if not variant.patch_ids.is_empty() or preset == null or str(variant.text) != expected_expression or variant.has("flow_draft"):
				return PackedStringArray(["Independent event expressions must retain their registered preset"])
			continue
		if not variant.get("flow_draft") is Dictionary or not variant.get("meaning") is String or not variant.get("meaning_id") is String or not variant.get("language_versions") is Array:
			return PackedStringArray(["Saved compositions require their draft, meaning and language versions"])
		var draft: Dictionary = variant.flow_draft
		if not draft.get("flow_skill_ids") is Array:
			return PackedStringArray(["Saved transmission skills must be an array"])
		var skill_ids := {}
		for skill_id: Variant in draft.flow_skill_ids:
			if not skill_id is String or skill_ids.has(skill_id):
				return PackedStringArray(["Saved transmission skill IDs must be unique strings"])
			skill_ids[skill_id] = true
		var decoded := _draft_from_json(draft, errors)
		if not errors.is_empty(): return errors
		errors.append_array(simulation.validate_draft(decoded))
		if not errors.is_empty(): return errors
		var composed: Dictionary
		if bool(variant.get("deviation_split", false)):
			if variant.parent_ids.size() != 1 or competition._canonical(draft) != competition._canonical(variant.get("mutation_parent_content", {}).get("flow_draft", {})):
				return PackedStringArray(["A drift split must retain its recorded source expression"])
			composed = ExpressionText.compose(catalog, draft)
		elif str(variant.creator) == "player":
			if variant.patch_ids != MutationRules.authored_patch_ids(draft) or (draft.has("patch_ids") and draft.patch_ids != variant.patch_ids):
				return PackedStringArray(["Player expression patches must match the author record"])
			composed = ExpressionText.compose(catalog, draft)
		else:
			if variant.parent_ids.size() != 1:
				return PackedStringArray(["A mutation must have one source version"])
			var parent: Dictionary = variant.get("mutation_parent_content", variants_by_id[variant.parent_ids[0]])
			var inherited: Array = parent.patch_ids
			var definition := simulation._event_definition(str(variant.get("mutation_definition_id", ""))) as MemeDemoEvent
			var expression_only := definition != null and definition.mutation_kind == &"expression"
			if variant.has("translation_version") and (not _integer(variant.translation_version) or variant.translation_version not in [1, EventMutation.TRANSLATION_VERSION] or not expression_only or definition.mutation_expression_mode != &"translation"):
				return PackedStringArray(["A saved translation requires its recorded rewrite version"])
			var translation_version := int(variant.get("translation_version", 1))
			var added_patches := 0 if expression_only else 1
			if not parent.get("flow_draft") is Dictionary or variant.patch_ids.size() != inherited.size() + added_patches or variant.patch_ids.slice(0, inherited.size()) != inherited:
				return PackedStringArray(["A mutation must preserve its parent's patches and add one patch"])
			if parent.flow_draft.get("reuse_permission", "unknown") == "restricted":
				return PackedStringArray(["A restricted source version cannot produce a community rewrite"])
			var mutation := EventMutation.derive(catalog, parent, str(variant.get("mutation_patch_id", "")), definition, draft.has("community_rephrase"), translation_version) if definition != null else MutationRules.derive(catalog, parent, str(variant.patch_ids.back()), draft.has("community_rephrase"))
			if mutation.is_empty(): return PackedStringArray(["A saved rewrite requires a compatible event mutation"])
			if definition != null and definition.mutation_kind == &"confluence":
				var companion_id := str(variant.get("confluence_source_id", ""))
				if not variants_by_id.has(companion_id) or companion_id == str(parent.id): return PackedStringArray(["Confluence requires its actual second circulating meme"])
				mutation = EventMutation.merge_with(mutation, variant.get("confluence_companion_content", variants_by_id[companion_id]), draft.has("confluence_contents"))
			if mutation.is_empty() or competition._canonical(draft) != competition._canonical(mutation.flow_draft):
				return PackedStringArray(["A mutation draft must match its inherited expression and new patch"])
			composed = mutation.composition
		if composed.is_empty(): return PackedStringArray(["Saved expression has no compatible composition"])
		for field: String in ["meaning", "meaning_id", "language_versions"]:
			if competition._canonical(variant[field]) != competition._canonical(composed[field]):
				errors.append("Saved composition differs from its expression patches: " + field)
		if str(variant.text) != str(composed.expression): errors.append("Saved expression differs from its patches")
		if not errors.is_empty(): return errors
	return errors


# Historical revisions remain immutable; live meme identity and effect rollback are checked separately.
func _validate_meme_lifecycle(data: Dictionary, variants_by_id: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var active_ids := {}
	var split_names := {}
	for variant: Dictionary in data.variants:
		if not variant.has("meme_id"):
			for field: String in ["meme_name", "deviation_anchor", "retired", "split_distance", "effective_content", "rollback_from_id", "split_from_id"]:
				if variant.has(field): errors.append("Saved meme lifecycle metadata is incomplete: " + field)
			continue
		if not variant.meme_id is String or str(variant.meme_id).is_empty() or not variant.get("meme_name") is String or str(variant.get("meme_name", "")).is_empty() or not variant.get("deviation_anchor") is Dictionary or not variant.get("retired") is bool or not _number(variant.get("split_distance")) or not _integer(variant.get("meme_name_index", -1)):
			errors.append("Saved meme identity, anchor or lifecycle field has the wrong type")
			continue
		var meme_id := str(variant.meme_id)
		var id := str(variant.id)
		if not variants_by_id.has(meme_id) or str(variants_by_id[meme_id].get("meme_id", "")) != meme_id:
			errors.append("Saved meme identity must reference its independent birth revision")
			continue
		var birth: Dictionary = variants_by_id[meme_id]
		var anchor: Dictionary = variant.deviation_anchor
		_validate_semantic_anchor(anchor, errors)
		if not errors.is_empty(): continue
		if competition._canonical(anchor) != competition._canonical(birth.get("deviation_anchor", {})) or not is_zero_approx(MonitorMetrics.deviation(anchor, birth)):
			errors.append("Saved meme deviations must use the unchanged birth expression")
		var threshold: float = MonitorMetrics.SPLIT_THRESHOLD
		if not variant.parent_ids.is_empty(): threshold = _mutation_threshold(variant, variants_by_id[str(variant.parent_ids[0])], variants_by_id, data, errors)
		if not errors.is_empty(): continue
		var metric_version := int(variant.get("mutation_policy", {}).get("metric_version", 1))
		var trigger := float(variant.split_distance)
		if variant.has("legacy_identity") and (not variant.legacy_identity is bool or not variant.legacy_identity or id != meme_id or not is_zero_approx(trigger) or variant.has("split_from_id")): errors.append("Legacy meme initialization must retain its pre-existing independent expression")
		if trigger < 0.0 or trigger > 1.0:
			errors.append("Saved meme split distance is outside zero to one")
		if id == meme_id and not variant.parent_ids.is_empty() and not bool(variant.get("legacy_identity", false)):
			if trigger <= threshold or not variant.get("split_from_id") is String or not variants_by_id.has(str(variant.get("split_from_id", ""))):
				errors.append("A new derived meme requires an observed deviation strictly above its recorded propagation threshold")
			else:
				var source: Dictionary = variants_by_id[str(variant.split_from_id)]
				var expected_trigger := clampf(MonitorMetrics.deviation(source.get("deviation_anchor", source), variant, metric_version) + float(variant.get("mutation_policy", {}).get("deviation_adjustment", 0.0)), 0.0, 1.0)
				if not is_equal_approx(trigger, expected_trigger): errors.append("Saved split trigger differs from the actual source expression")
				if str(variant.meme_name) == str(source.get("meme_name", "")) or not str(variant.meme_name).begins_with("MEME_SPLIT_NAME_"):
					errors.append("A split meme requires an independent name")
				var name_index := int(variant.get("meme_name_index", -1))
				if name_index < 0 or str(variant.meme_name) != "MEME_SPLIT_NAME_%02d" % (name_index % 16): errors.append("Saved split name does not match its independent name index")
				if split_names.has(name_index): errors.append("Split meme names must be unique")
				split_names[name_index] = id
			if not is_zero_approx(float(variant.semantic_distance)): errors.append("A newborn independent meme starts at zero deviation")
		elif id != meme_id:
			if trigger > threshold or variant.parent_ids.is_empty() or str(variants_by_id[str(variant.parent_ids[0])].get("meme_id", "")) != meme_id:
				errors.append("A non-split revision must retain its source meme identity")
			if not is_equal_approx(trigger, clampf(MonitorMetrics.deviation(anchor, variant, metric_version) + float(variant.get("mutation_policy", {}).get("deviation_adjustment", 0.0)), 0.0, 1.0)):
				errors.append("Saved revision deviation differs from its expression")
		var observed_deltas: Dictionary = variant.get("split_effect_deltas", {}) if variant.has("split_from_id") else variant.get("deviation_effect_deltas", {})
		var expected_deltas := {} if variant.has("rollback_from_id") else _recorded_effect_deltas(variant, variants_by_id)
		var observed_patches: Dictionary = variant.get("split_patch_effects", {}) if variant.has("split_from_id") else variant.get("deviation_patch_effects", {})
		var expected_patches := {} if variant.has("rollback_from_id") else _recorded_patch_effects(variant, variants_by_id)
		if not _equal_patch_effects(observed_patches, expected_patches): errors.append("Saved per-patch effects differ from their actual authored records")
		if not _equal_effect_deltas(observed_deltas, expected_deltas): errors.append("Saved deviation effects differ from their actual authored patches")
		if variant.has("split_from_id") and (not _equal_effect_deltas(variant.get("deviation_effect_deltas", {}), {}) or not _equal_patch_effects(variant.get("deviation_patch_effects", {}), {})): errors.append("A newborn independent meme starts without pending rollback effects")
		if not variant.retired:
			if active_ids.has(meme_id): errors.append("A meme may have only one live revision")
			active_ids[meme_id] = id
		else:
			for country: Dictionary in data.competition_state.countries.values():
				for field: String in ["adopted", "exposed", "attention"]:
					if int(country[field].get(id, 0)) != 0: errors.append("A retired revision cannot retain map population or attention")
		var entry: Dictionary = data.competition_state.registry[id]
		if not variant.get("effective_content", {}) is Dictionary:
			errors.append("Saved live effect overrides must be a dictionary")
			continue
		var effective: Dictionary = variant.get("effective_content", {})
		for field: String in effective:
			if field not in ["text", "meaning", "meaning_id", "language_versions", "patch_ids", "language_id", "topic_ids", "political_known", "political_position", "pragmatic_position", "context_layer_attachment", "flow_draft", "flow_profile", "creator", "owned", "controlled", "semantic_distance"]:
				errors.append("Saved effect overrides cannot replace identity or history: " + field)
		if variant.has("live_author_edit"):
			var expected := _recorded_author_content(variant, variant.live_author_edit, data)
			if expected.is_empty() or competition._canonical(effective) != competition._canonical(expected):
				errors.append("Live author content must match its recorded design operations")
				continue
			if competition._canonical(effective.flow_profile) != competition._canonical(entry.get("effective_profile", {})):
				errors.append("Live author propagation differs from its current expression")
			_validate_live_profile(effective.flow_profile, errors)
		elif effective.has("flow_profile"):
			if not effective.flow_profile is Dictionary or not variant.get("rollback_from_id") is String or not variants_by_id.has(str(variant.get("rollback_from_id", ""))):
				errors.append("Effect rollback requires its actual split source and live profile")
				continue
			var candidate: Dictionary = variants_by_id[str(variant.rollback_from_id)]
			var expected: Dictionary = MemeLifecycle.rollback_content(anchor, candidate)
			for field: String in ["creator", "owned", "controlled"]: expected[field] = birth[field]
			if competition._canonical(effective) != competition._canonical(expected): errors.append("Saved rollback changed unrelated effects or failed to restore its initial expression")
			if not is_zero_approx(MonitorMetrics.deviation(anchor, MemeLifecycle.content(variant))): errors.append("The original meme must reset to zero deviation after splitting")
			if competition._canonical(effective.flow_profile) != competition._canonical(entry.get("effective_profile", {})):
				errors.append("Live propagation profile differs from the recorded semantic rollback")
			_validate_live_profile(effective.flow_profile, errors)
		elif entry.has("effective_profile") and competition._canonical(entry.effective_profile) != competition._canonical(variant.flow_profile):
			errors.append("A custom live propagation profile requires a recorded effect rollback")
		if effective.has("creator") and (not effective.creator is String or str(effective.creator).is_empty()): errors.append("Live creator must remain a named participant")
		for field: String in ["owned", "controlled"]:
			if effective.has(field) and not effective[field] is bool: errors.append("Live ownership and control must be boolean")
		var live: Dictionary = MemeLifecycle.content(variant)
		for field: String in ["creator", "owned", "controlled"]:
			if live[field] != birth[field]: errors.append("A live revision must retain its independent meme ownership and control")
		if bool(live.controlled) and (str(live.creator) != "player" or not bool(live.owned)): errors.append("Only an owned player meme can remain directly controlled")
	for variant: Dictionary in data.variants:
		if variant.has("meme_id") and not active_ids.has(str(variant.meme_id)): errors.append("Saved meme has no live revision")
	var current_id := str(data.current_variant_id)
	if variants_by_id.has(current_id) and bool(variants_by_id[current_id].get("retired", false)): errors.append("The current meme must reference its live revision")
	return errors




func _equal_effect_deltas(actual: Dictionary, expected: Dictionary) -> bool:
	var fields := actual.duplicate()
	fields.merge(expected)
	for field: String in fields:
		if field not in MemeLifecycle.PATCH_SCALAR_FIELDS or not is_equal_approx(float(actual.get(field, 0.0)), float(expected.get(field, 0.0))): return false
	return true

func _effect_delta_candidate(variant: Dictionary) -> Dictionary:
	var candidate := variant.duplicate(true)
	for field: String in ["split_effect_deltas", "split_patch_effects", "deviation_effect_deltas", "deviation_patch_effects"]: candidate.erase(field)
	return candidate

func _recorded_effect_deltas(variant: Dictionary, variants_by_id: Dictionary) -> Dictionary:
	if variant.parent_ids.is_empty(): return {}
	var source: Dictionary = variants_by_id[str(variant.parent_ids[0])]
	return MemeLifecycle.effect_deltas(source.get("deviation_anchor", source), _effect_delta_candidate(variant), source)

func _recorded_patch_effects(variant: Dictionary, variants_by_id: Dictionary) -> Dictionary:
	if variant.parent_ids.is_empty(): return {}
	var source: Dictionary = variants_by_id[str(variant.parent_ids[0])]
	return MemeLifecycle.patch_effects(source.get("deviation_anchor", source), _effect_delta_candidate(variant), source)

func _equal_patch_effects(actual: Dictionary, expected: Dictionary) -> bool:
	var patches := actual.duplicate()
	patches.merge(expected)
	for patch: String in patches:
		if not _equal_effect_deltas(actual.get(patch, {}), expected.get(patch, {})): return false
	return true

func _validate_lifecycle_field_types(variants: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	for variant: Dictionary in variants:
		if not variant.has("meme_id"): continue
		if not variant.get("deviation_anchor") is Dictionary or not variant.get("effective_content", {}) is Dictionary or not variant.get("flow_profile") is Dictionary:
			errors.append("Saved lifecycle effect and anchor fields must be dictionaries")
			continue
		for key: String in ["flow_draft", "flow_profile"]:
			if not variant.deviation_anchor.get(key) is Dictionary:
				errors.append("Saved semantic anchor configurations must be dictionaries")
			if variant.get("effective_content", {}).has(key) and not variant.get("effective_content", {})[key] is Dictionary:
				errors.append("Saved effect override configurations must be dictionaries")
		_validate_semantic_anchor(variant.deviation_anchor, errors)
		for field: String in ["deviation_patch_effects", "split_patch_effects"]:
			if not variant.get(field, {}) is Dictionary:
				errors.append("Saved per-patch effects must be a dictionary")
				continue
			for patch: Variant in variant.get(field, {}):
				if not patch is String or not variant[field][patch] is Dictionary:
					errors.append("Saved per-patch effects must contain named delta maps")
					continue
				for key: Variant in variant[field][patch]:
					if not key is String or not _number(variant[field][patch][key]): errors.append("Saved per-patch effects must contain finite named values")
		for field: String in ["deviation_effect_deltas", "split_effect_deltas"]:
			if not variant.get(field, {}) is Dictionary:
				errors.append("Saved deviation effect deltas must be a dictionary")
				continue
			for key: Variant in variant.get(field, {}):
				if not key is String or not _number(variant[field][key]): errors.append("Saved deviation effect deltas must contain finite named values")
	return errors

func _validate_content_snapshots(data: Dictionary, variants_by_id: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for variant: Dictionary in data.variants:
		if variant.has("mutation_parent_content"):
			if not variant.mutation_parent_content is Dictionary or variant.parent_ids.is_empty():
				errors.append("Mutation history requires its actual source content snapshot")
				continue
			var source: Dictionary = variants_by_id[str(variant.parent_ids[0])]
			if not _is_recorded_content(variant.mutation_parent_content, source, data.variants, variants_by_id, data):
				errors.append("Mutation source content differs from its recorded expression history")
		if variant.has("confluence_companion_content"):
			var companion_id := str(variant.get("confluence_source_id", ""))
			if not variant.confluence_companion_content is Dictionary or not variants_by_id.has(companion_id) or not _is_recorded_content(variant.confluence_companion_content, variants_by_id[companion_id], data.variants, variants_by_id, data):
				errors.append("Confluence companion content differs from its immutable expression history")
		if not errors.is_empty(): return errors
		if variant.has("effective_history"):
			if not variant.effective_history is Array:
				errors.append("Effect rollback history must be an array")
				continue
			for historical: Variant in variant.effective_history:
				if not historical is Dictionary or not _is_recorded_content(historical, variant, data.variants, variants_by_id, data):
					errors.append("Historical rollback content must reconstruct from an actual split")
		if not errors.is_empty(): return errors
	var event_copies: Array = data.events.duplicate()
	event_copies.append_array(data.pending_events)
	if not data.active_event.is_empty(): event_copies.append(data.active_event)
	for event: Dictionary in event_copies:
		if not event.has("target_content_snapshot"): continue
		var target_id := str(event.get("target_variant_id", ""))
		if target_id.is_empty() and event.target_content_snapshot is Dictionary and event.target_content_snapshot.is_empty(): continue
		if not variants_by_id.has(target_id) or not event.target_content_snapshot is Dictionary or not _is_recorded_content(event.target_content_snapshot, variants_by_id[target_id], data.variants, variants_by_id, data):
			errors.append("Event target content differs from its immutable expression history")
	return errors


func _validate_endgame(data: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var state: Dictionary = data.endgame
	if state.size() != 4 or not state.has_all(["war_started", "war_started_hour", "carrier_country_ids", "collapse_hours"]) or not state.get("war_started") is bool or not _integer(state.get("war_started_hour")) or not state.get("carrier_country_ids") is Array or not state.get("collapse_hours") is Dictionary:
		return PackedStringArray(["Saved endgame state has invalid fields or types"])
	var world: Dictionary = data.competition_state
	var rules: MemeGameplayRules = catalog.gameplay_rules
	var trigger_hour := ceili(rules.fallback_war_seconds * rules.hours_per_active_second)
	var target_meme_id := ""
	for variant: Dictionary in data.variants:
		if str(variant.id) == str(data.current_variant_id):
			target_meme_id = str(variant.get("meme_id", variant.id))
			break
	if str(world.ending_progress.get("target_meme_id", "")) != target_meme_id:
		return PackedStringArray(["Saved ending progress must track the current independent meme"])
	var country_ids: Array = []
	for row: Dictionary in world.world: country_ids.append(str(row.id))
	var war_events: Array = []
	for event: Dictionary in data.events:
		if str(event.definition_id) == "world_war_three": war_events.append(event)
	if data.phase == "complete":
		if not _integer(data.ending.get("hour")) or int(data.ending.get("hour", -1)) != int(data.hour): errors.append("Saved ending must match the completed run's hour")
	elif not data.ending.is_empty(): errors.append("An unfinished run cannot contain a completed ending")
	if not bool(state.war_started):
		if int(state.war_started_hour) != -1 or not state.carrier_country_ids.is_empty() or not state.collapse_hours.is_empty() or not war_events.is_empty(): errors.append("A peaceful run cannot contain a war schedule or announcement")
		for row: Dictionary in world.world:
			if int(world.populations[str(row.id)]) != int(row.population): errors.append("A peaceful country's population differs from its initial population")
		if data.phase == "complete":
			if str(data.ending.get("id", "")) not in ["viral_icon", "local_classic", "balanced_duel", "successful_adaptation", "forgotten", "best_substitute"] or competition._canonical(data.ending) != competition._canonical(world.victory): errors.append("A normal ending must match its verified competition outcome")
			if int(data.hour) > trigger_hour: errors.append("A normal ending is later than the world war deadline")
		elif int(data.hour) >= trigger_hour or not world.victory.is_empty(): errors.append("An unfinished peaceful run has passed the war deadline or already reached an ending")
		return errors
	if int(state.war_started_hour) != trigger_hour or int(data.hour) < trigger_hour:
		return PackedStringArray(["Saved world war must start at the configured deadline"])
	if competition._canonical(state.collapse_hours) != competition._canonical(WorldWar.schedule(int(data.seed), country_ids, rules.world_war_min_country_hours, rules.world_war_duration_hours)):
		return PackedStringArray(["Saved country collapse schedule differs from its seed and rules"])
	var carriers := {}
	for id: Variant in state.carrier_country_ids:
		if not id is String or id not in country_ids or carriers.has(id): errors.append("Saved war carriers must contain unique world country identifiers")
		else: carriers[id] = true
	if not errors.is_empty(): return errors
	if war_events.size() != 1:
		return PackedStringArray(["A world war requires exactly one recorded announcement"])
	var announcement: Dictionary = war_events[0]
	if int(announcement.hour) != trigger_hour or competition._canonical(announcement.get("carrier_country_ids")) != competition._canonical(state.carrier_country_ids): errors.append("The world war announcement differs from its start or carrier snapshot")
	if bool(announcement.acknowledged):
		if data.phase not in ["running", "complete"]: errors.append("An acknowledged world war cannot remain in an event or draft phase")
	elif data.phase != "event" or data.active_event.get("instance_id") != announcement.instance_id or int(data.hour) != trigger_hour:
		errors.append("An unacknowledged war announcement must be the active event at its start")
	if not world.victory.is_empty(): errors.append("A wartime run cannot claim a normal competition ending")
	var elapsed := int(data.hour) - int(state.war_started_hour)
	var total_population := 0
	var carrier_population := 0
	var current_carriers := WorldWar.carrier_countries(data.variants, world.countries, str(data.current_variant_id))
	for id: String in current_carriers:
		if not carriers.has(id): errors.append("The war carrier snapshot omits a country still carrying the current meme")
	for row: Dictionary in world.world:
		var id := str(row.id)
		var population := int(world.populations[id])
		if population != WorldWar.population(int(row.population), elapsed, int(state.collapse_hours[id])): errors.append("Saved wartime population differs from its country's collapse schedule")
		total_population += population
		if carriers.has(id): carrier_population += population
	var expected_ending := "world_extinction" if total_population == 0 else "player_extinction" if not carriers.is_empty() and carrier_population == 0 else ""
	if data.phase == "complete":
		if expected_ending.is_empty() or data.ending.size() != 3 or str(data.ending.get("id", "")) != expected_ending or not _integer(data.ending.get("war_started_hour")) or int(data.ending.get("war_started_hour", -1)) != trigger_hour:
			errors.append("A catastrophe ending must follow actual world or player-carrier extinction")
	elif not expected_ending.is_empty(): errors.append("An extinct world or player carrier population must already be settled")
	return errors


func _same_content_snapshot(actual: Dictionary, expected: Dictionary) -> bool:
	var a := actual.duplicate(true)
	var b := expected.duplicate(true)
	for record: Dictionary in [a, b]:
		for field: String in ["deviation_effect_deltas", "deviation_patch_effects"]:
			if record.get(field, {}) is Dictionary and record.get(field, {}).is_empty(): record.erase(field)
	return competition._canonical(a) == competition._canonical(b)

func _recorded_author_content(source: Dictionary, record: Variant, data: Dictionary) -> Dictionary:
	if not record is Dictionary or record.size() != 3 or record.get("schema") != 1 or not _integer(record.get("operation_count")) or not _integer(record.get("hour")): return {}
	var count := int(record.operation_count)
	if count <= 0 or count > data.design_state.operations.size() or int(record.hour) < 0 or int(record.hour) > int(data.hour): return {}
	if not _author_configurations.has(count):
		var ledger := DesignState.new(catalog)
		ledger._state = data.design_state.duplicate(true)
		_author_configurations[count] = ledger.recorded_configuration(count, data.events, data.variants)
	var configuration: Dictionary = _author_configurations[count]
	if configuration.is_empty(): return {}
	if not bool(MemeLifecycle.content(source).get("owned", false)) or str(configuration.draft.kernel_id) != str(source.kernel_id) or str(configuration.draft.preset_id) != str(source.preset_id): return {}
	return simulation._live_author_content(configuration.draft, configuration.skills, source)

func _is_recorded_content(snapshot: Dictionary, source: Dictionary, variants: Array, variants_by_id: Dictionary, data: Dictionary) -> bool:
	var pristine := source.duplicate(true)
	pristine.erase("effective_content")
	pristine.erase("live_author_edit")
	if source.has("meme_id"):
		pristine.deviation_effect_deltas = {} if str(source.meme_id) == str(source.id) else _recorded_effect_deltas(source, variants_by_id)
		pristine.deviation_patch_effects = {} if str(source.meme_id) == str(source.id) else _recorded_patch_effects(source, variants_by_id)
	if snapshot.has("live_author_edit"):
		var authored := _recorded_author_content(source, snapshot.live_author_edit, data)
		if authored.is_empty(): return false
		var reconstructed := pristine.duplicate(true)
		reconstructed.effective_content = authored
		reconstructed.live_author_edit = snapshot.live_author_edit.duplicate(true)
		if _same_content_snapshot(snapshot, MemeLifecycle.revision_snapshot(reconstructed)): return true
		for candidate: Dictionary in variants:
			if str(candidate.get("split_from_id", "")) != str(source.id): continue
			reconstructed.deviation_effect_deltas = {}
			reconstructed.deviation_patch_effects = {}
			if _same_content_snapshot(snapshot, MemeLifecycle.revision_snapshot(reconstructed)): return true
		return false
	if _same_content_snapshot(snapshot, MemeLifecycle.revision_snapshot(pristine)): return true
	if not source.get("deviation_anchor") is Dictionary: return false
	var birth_id := str(source.get("meme_id", source.id))
	if not variants_by_id.has(birth_id): return false
	var birth: Dictionary = variants_by_id[birth_id]
	var same_identity := pristine.duplicate(true)
	same_identity.effective_content = {}
	for field: String in ["creator", "owned", "controlled"]: same_identity.effective_content[field] = birth[field]
	if _same_content_snapshot(snapshot, MemeLifecycle.revision_snapshot(same_identity)): return true
	for candidate: Dictionary in variants:
		if str(candidate.get("split_from_id", "")) != str(source.id): continue
		var expected: Dictionary = MemeLifecycle.rollback_content(source.deviation_anchor, candidate)
		for field: String in ["creator", "owned", "controlled"]: expected[field] = birth[field]
		var reconstructed := source.duplicate(true)
		reconstructed.erase("live_author_edit")
		reconstructed.effective_content = expected
		reconstructed.deviation_effect_deltas = {}
		reconstructed.deviation_patch_effects = {}
		if _same_content_snapshot(snapshot, MemeLifecycle.revision_snapshot(reconstructed)): return true
	return false

func _validate_semantic_anchor(anchor: Dictionary, errors: PackedStringArray) -> void:
	if not anchor.get("text") is String or not anchor.get("meaning", "") is String or not anchor.get("meaning_id", "") is String or not anchor.get("flow_profile") is Dictionary:
		errors.append("A meme deviation anchor requires its original expression and semantic profile")
		return
	var profile: Dictionary = anchor.flow_profile
	for key: String in ["political_position", "pragmatic_position"]:
		if not profile.get(key) is Array or profile[key].size() != 2:
			errors.append("Saved semantic anchor coordinates must contain two numbers")
		else:
			for value: Variant in profile[key]:
				if not _number(value) or absf(float(value)) > 1.0: errors.append("Saved semantic anchor coordinates are invalid")
	if not profile.get("political_known") is bool or not profile.get("topic_ids") is Array:
		errors.append("Saved semantic anchor context has the wrong type")
	for layer: String in ["language", "group"]:
		if not profile.get(layer + "_id") is String: errors.append("Saved semantic anchor audience identity has the wrong type")
		if profile.has(layer + "_ids"):
			if not profile[layer + "_ids"] is Array: errors.append("Saved semantic anchor audiences must be arrays")
			else:
				for value: Variant in profile[layer + "_ids"]:
					if not value is String: errors.append("Saved semantic anchor audiences must contain strings")

func _validate_live_profile(profile: Dictionary, errors: PackedStringArray) -> void:
	errors.append_array(competition.propagation_rules.validate_profile(profile))
	for key: String in ["language_access", "recognizability", "context_dependency", "remix_cost", "expression"]:
		if not _number(profile.get(key)) or float(profile.get(key, -1.0)) < 0.0 or float(profile.get(key, 2.0)) > 1.0:
			errors.append("Invalid live propagation parameter: " + key)
	if not _number(profile.get("reach")) or float(profile.get("reach", 0.0)) <= 0.0: errors.append("Live reach must be finite and positive")
	for key: String in ["language_id", "group_id", "channel_id", "text"]:
		if not profile.get(key) is String: errors.append("Invalid live propagation identity: " + key)
	if not profile.get("skill_ids") is Array: errors.append("Live propagation skills must be an array")
	else:
		for skill: Variant in profile.skill_ids:
			if skill not in catalog.gameplay_rules.skill_reach: errors.append("Live propagation skill is not registered")
	_validate_semantic_anchor({"text":profile.get("text", ""), "flow_profile":profile}, errors)
	if profile.get("topic_ids") is Array:
		for topic: Variant in profile.topic_ids:
			if topic not in catalog.topics: errors.append("Live propagation topic is not registered")
	if not profile.get("context_layer_attachment") is Dictionary or profile.context_layer_attachment.size() != 5:
		errors.append("Live context attachment must describe all five layers")
	else:
		for layer: String in ["language", "group", "topics", "stance", "pragmatic"]:
			if not profile.context_layer_attachment.get(layer) is bool: errors.append("Live context attachments must be boolean")

func _validate_preset_sources(entry: Dictionary, label: String, errors: PackedStringArray) -> void:
	if not entry.get("preset_id", "") is String or not entry.get("source_presets") is Array:
		errors.append(DeskLocalization.source_format("LOC_WRONG_PRESET_SOURCE_FIELD_TYPE_IN_SAVED_449A9157", label))
		return
	var preset_id: String = entry.get("preset_id", "")
	var sources: Array = entry.source_presets
	if preset_id.is_empty():
		if not sources.is_empty(): errors.append(DeskLocalization.source_format("LOC_SAVED_S_CLAIMS_A_CASE_SOURCE_WITHOUT_9000550F", label))
		return
	var preset := catalog.find_preset(preset_id)
	if preset == null:
		errors.append(DeskLocalization.source_format("LOC_SAVED_S_REFERENCES_AN_UNKNOWN_PRESET_35BD6358", label))
	elif sources.size() != 1 or not sources[0] is Dictionary or sources[0] != preset.source_record():
		errors.append(DeskLocalization.source_format("LOC_SAVED_S_CASE_SOURCE_DOES_NOT_MATCH_78BD2135", label))

func _validate_event_copy(event: Dictionary, errors: PackedStringArray) -> void:
	if event.has("target_content_snapshot") and not event.target_content_snapshot is Dictionary:
		errors.append("Saved event target snapshots must be dictionaries")
		return
	for key in ["instance_id", "definition_id", "title", "narrative", "effect_text", "origin", "impact_text", "mentor_comment", "design_source_preset_id", "reward_text"]:
		if not event.get(key) is String: errors.append(DeskLocalization.source("LOC_WRONG_SAVED_EVENT_TEXT_TYPE_5170C9D1") + key)
	if not _integer(event.get("hour")) or not event.get("discoveries") is Array or not event.get("acknowledged") is bool or not event.get("design_rewards") is Array or not event.get("competition_variant_ids") is Array:
		errors.append(DeskLocalization.source("LOC_INVALID_SAVED_EVENT_RECORD_FIELDS_F4888510"))
	if not errors.is_empty(): return
	for key in ["discoveries", "competition_variant_ids"]:
		for identity: Variant in event[key]:
			if not identity is String: errors.append(DeskLocalization.source("LOC_SAVED_EVENT_REFERENCES_MUST_USE_STRING_IDENTIFIERS_03E3072F"))
	var definition: MemeDemoEvent = null
	for candidate: MemeDemoEvent in catalog.events:
		if str(candidate.id) == event.definition_id: definition = candidate
	if definition == null:
		errors.append(DeskLocalization.source("LOC_THE_EVENT_DEFINITION_IS_NOT_IN_THE_8062767A"))
		return
	if str(definition.id) == "world_war_three":
		if not event.get("carrier_country_ids") is Array: errors.append("The world war event must preserve its carrier-country snapshot")
	elif event.has("carrier_country_ids"): errors.append("Only the world war event may contain a carrier-country snapshot")
	if not event.get("country_id") is String or not event.get("country_title") is String or event.get("category") != str(definition.category) or not event.get("response") is Dictionary or not event.get("applied_effects") is Array or not _number(event.get("response_duration_hours")):
		errors.append("Saved events require their country, category and resolved response")
		return
	var country: Dictionary = catalog.gameplay_rules.country(str(event.country_id))
	if country.is_empty():
		errors.append("Saved event country is not in the world")
		return
	var resolved := EventResponse.resolve(definition, country, catalog.groups)
	if definition.origin == &"transmission": resolved.topic_ids = event.response.get("topic_ids", [])
	if competition._canonical(event.response) != competition._canonical(resolved): errors.append("Saved event response differs from its country and definition")
	if event.country_title != simulation._event_country_title(str(event.country_id)): errors.append("Saved event country title differs from its origin")
	var narrative := DeskLocalization.source_format(definition.narrative, str(event.country_title), [0]) if "%s" in definition.narrative else definition.narrative
	if event.narrative != narrative or event.title != definition.title or event.origin != str(definition.origin): errors.append("Saved event identity differs from its definition")
	if event.response_duration_hours != maxf(1.0, simulation._event_hours(definition.attention_duration_hours)): errors.append("Saved response duration differs from its definition")
	var expected_effects: Array = []
	for effect: MemeDemoEffect in definition.effects:
		expected_effects.append({"effect_id":str(effect.effect_id), "amount":effect.amount, "duration_hours":maxf(1.0, simulation._event_hours(effect.duration_hours)), "group_ids":Array(effect.group_ids), "country_id":str(event.country_id), "target_variant_id":str(event.get("target_variant_id", ""))})
	if competition._canonical(event.applied_effects) != competition._canonical(expected_effects): errors.append("Saved effects differ from their country and target")
	var actual := JSON.stringify(JSON.parse_string(JSON.stringify(event.design_rewards)), "", true, true)
	var expected := JSON.stringify(JSON.parse_string(JSON.stringify(definition.design_rewards)), "", true, true)
	# An empty delivery is checked against the unique-card history below.
	if (actual != expected and not event.design_rewards.is_empty()) or event.design_source_preset_id != str(definition.external_preset_id): errors.append(DeskLocalization.source("LOC_EVENT_SUPPLY_OR_PRESET_SOURCE_CONFLICTS_WITH_2FE2F3F5"))
	var expected_text: String = ((DeskLocalization.source("LOC_CLAIMED_9C9021A0") if event.acknowledged else DeskLocalization.source("LOC_EVENT_MATERIALS")) + simulation._reward_summary(event.design_rewards)) if not event.design_rewards.is_empty() else ""
	if event.reward_text != expected_text: errors.append(DeskLocalization.source("LOC_EVENT_SUPPLY_TEXT_DOES_NOT_MATCH_ITS_038EBF27"))
	for field in ["impact_text", "mentor_comment"]:
		if str(event[field]).strip_edges().is_empty(): errors.append(DeskLocalization.source("LOC_SAVED_EVENT_TEXT_IS_EMPTY_BD4C7C07") + field)
	if "\n" in event.mentor_comment or "\r" in event.mentor_comment: errors.append(DeskLocalization.source("LOC_S_SAVED_COMMENT_IS_NOT_A_SINGLE_0A288143"))

## 调度计数必须来自真实事件历史，内部据此直接读取最后触发时间。
func _validate_event_history(data: Dictionary, errors: PackedStringArray) -> void:
	var instance_ids := {}
	var observed_counts := {}
	var observed_hours := {}
	var initial := DesignState.new(catalog)
	var starter := str(data.design_state.get("starter_preset_id",""))
	if not starter.is_empty():
		errors.append_array(initial.perform("choose_starter",{"preset_id":starter}))
		if not errors.is_empty(): return
	var reserved: Array = []
	var records := {}
	for event: Dictionary in data.events:
		if event.instance_id.is_empty() or instance_ids.has(event.instance_id): errors.append(DeskLocalization.source("LOC_A_SAVED_EVENT_INSTANCE_HAS_AN_EMPTY_3FC63291"))
		if event.hour < 0 or event.hour > data.hour: errors.append(DeskLocalization.source("LOC_A_SAVED_EVENT_TIME_IS_OUTSIDE_THE_09D4A40A"))
		instance_ids[event.instance_id] = true
		observed_counts[event.definition_id] = int(observed_counts.get(event.definition_id, 0)) + 1
		observed_hours[event.definition_id] = int(event.hour)
		var definition: MemeDemoEvent = simulation._event_definition(str(event.definition_id))
		var expected := initial.unique_event_rewards(definition.design_rewards,reserved)
		if competition._canonical(event.design_rewards) != competition._canonical(expected): errors.append(DeskLocalization.source("LOC_EVENT_SUPPLY_OR_PRESET_SOURCE_CONFLICTS_WITH_2FE2F3F5"))
		reserved.append(event)
		records[event.instance_id] = event
	var queued: Array = data.pending_events.duplicate()
	if not data.active_event.is_empty(): queued.append(data.active_event)
	var queued_ids := {}
	if not data.active_event.is_empty() and data.phase != "event": errors.append(DeskLocalization.source("LOC_EVENT_QUEUE_STATE_MISMATCH"))
	for event: Dictionary in queued:
		if not records.has(event.instance_id) or competition._canonical(event) != competition._canonical(records[event.instance_id]): errors.append(DeskLocalization.source("LOC_EVENT_QUEUE_STATE_MISMATCH"))
		if event.acknowledged or queued_ids.has(event.instance_id): errors.append(DeskLocalization.source("LOC_EVENT_QUEUE_STATE_MISMATCH"))
		queued_ids[event.instance_id] = true
	for event: Dictionary in data.events:
		if not event.acknowledged and not queued_ids.has(event.instance_id): errors.append(DeskLocalization.source("LOC_EVENT_QUEUE_STATE_MISMATCH"))
	if competition._canonical(data.event_counts) != observed_counts or competition._canonical(data.last_event_hours) != observed_hours:
		errors.append(DeskLocalization.source("LOC_SAVED_EVENT_SCHEDULING_COUNTS_OR_TIMES_DO_F90F1850"))

func _validate_guidance_progress(data: Dictionary) -> PackedStringArray:
	var progress: Variant = data.guide_progress
	var invalid := PackedStringArray([DeskLocalization.source("LOC_INVALID_GUIDANCE_PROGRESS")])
	if not progress is Dictionary or progress.size() > 4: return invalid
	for id: Variant in progress:
		if id not in ["fax","competition","mutation","deviation"]: return invalid
		var entry: Variant = progress[id]
		if not entry is Dictionary or entry.size() != 2 or not entry.get("source_id") is String or not entry.get("shown") is bool: return invalid
		if not simulation.guidance_source_valid(id,entry.source_id,data.events,data.variants): return invalid
	return PackedStringArray()

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
	if decoded.phase != "complete" and not bool(decoded.endgame.war_started):
		CompetitionState.IndependentEndings.refresh_metrics(restored_competition._state.ending_progress, decoded.variants, restored_competition)
	# 所有解析、转换和账本校验结束后，才替换当前局。
	simulation.competition = restored_competition
	simulation.design_state = restored_design
	simulation.economy = restored_economy
	simulation.seed_value = int(decoded.seed)
	simulation._rng.seed = simulation.seed_value
	simulation._rng.state = int(decoded.rng_state)
	simulation._event_clock_arrivals.clear()
	simulation._meme_trends.clear()
	simulation.hour = int(decoded.hour)
	simulation.run_end_hour = int(decoded.run_end_hour)
	simulation.speed = int(decoded.speed)
	simulation.resume_speed = int(decoded.resume_speed)
	simulation.publish_count = int(decoded.publish_count)
	simulation.phase = decoded.phase
	simulation.ending = decoded.ending.duplicate(true)
	simulation.endgame = decoded.endgame.duplicate(true)
	simulation.country_id = decoded.country_id
	simulation.country_title = decoded.country_title
	simulation.status = decoded.status
	simulation.current_variant_id = decoded.current_variant_id
	simulation.guide_progress = decoded.guide_progress.duplicate(true)
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
	return JSON.stringify({"catalog":_resource_data(catalog),"rewards":PropagationRewards.signature(),"propagation_content":FileAccess.get_file_as_string("res://data/propagation/content_profiles.json").sha256_text()}, "", true, true).sha256_text()

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
		errors.append(DeskLocalization.source("LOC_SAVE_LACKS_FLOATING_POINT_PRECISION_RECORDS_F4BF3B09"))
		return data
	var required: Dictionary = {}
	_collect_precision(data, "", required)
	for path in required:
		if not data.numeric_precision.has(path): errors.append(DeskLocalization.source("LOC_PRECISION_RECORD_IS_MISSING_FIELD_879629B4") + path)
	var seen: Dictionary = {}
	var decoded: Dictionary = _precise_value(data, "", data.numeric_precision, seen, errors)
	for path in data.numeric_precision:
		if not seen.has(path): errors.append(DeskLocalization.source("LOC_PRECISION_RECORD_REFERENCES_AN_UNKNOWN_FIELD_33743897"))
	return decoded

func _precise_value(value: Variant, path: String, precision: Dictionary, seen: Dictionary, errors: PackedStringArray) -> Variant:
	if precision.has(path):
		seen[path] = true
		var hex: Variant = precision[path]
		if not _number(value) or not hex is String or hex.length() != 16 or not hex.is_valid_hex_number(false):
			errors.append(DeskLocalization.source("LOC_INVALID_SAVED_FLOATING_POINT_PRECISION_FORMAT_035B22B2") + path)
			return value
		var exact: float = hex.hex_decode().decode_double(0)
		if not is_finite(exact) or absf(float(value) - exact) > maxf(0.000000001, absf(exact) * 0.00000000000001):
			errors.append(DeskLocalization.source("LOC_SAVED_FLOATING_POINT_PRECISION_DOES_NOT_MATCH_5EB2DD02") + path)
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
