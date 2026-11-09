extends RefCounted
## 当前存档格式的唯一边界：先解析和验证，再一次性安装完整候选状态。

const CompetitionState = preload("res://scripts/gameplay/competition/competition_state.gd")
const DesignState = preload("res://scripts/gameplay/design/design_state.gd")
const MutationRules = preload("res://scripts/gameplay/events/mutation_rules.gd")
const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")
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
	var decoded := _decode_precision(data, errors)
	if not errors.is_empty(): return {}
	# Guidance progress is optional in version-3 saves.
	if not decoded.has("guide_progress"): decoded.guide_progress = {}
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
	var dictionaries := ["latest_draft", "families", "group_state", "event_counts", "last_event_hours", "active_event", "attention", "economy", "design_state", "competition_state"]
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
	if not str(data.rng_state).is_valid_int() or data.phase not in ["draft", "running", "event", "complete"] or data.hour < 0 or data.hour > data.run_end_hour or data.run_end_hour < catalog.run_hours or data.speed < 0 or data.speed > 2 or data.resume_speed < 0 or data.resume_speed > 2 or data.publish_count < 0 or data.serial < 0 or data.draft_distance < 0 or data.draft_distance > 1:
		errors.append(DeskLocalization.source("LOC_THE_SAVED_PHASE_RANDOM_STATE_COUNT_OR_244F19E2"))
	if not errors.is_empty(): return errors
	errors.append_array(competition.validate_payload(data.competition_state, data.variants, int(data.hour)))
	if data.phase in ["event", "draft", "complete"] and data.speed != 0:
		errors.append(DeskLocalization.source("LOC_NON_RUNNING_PHASES_MUST_BE_PAUSED_03C4597B"))
	errors.append_array(economy.validate_payload(data.economy))
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
		for origin in variant.get("origin_ids", []):
			if not variant_ids.has(origin): errors.append(DeskLocalization.source("LOC_SAVED_ORIGINAL_VERSION_SOURCE_IS_MISSING_84500A57"))
			elif (not variant_ids[origin].parent_ids.is_empty() or str(variant_ids[origin].creator) != "player"): errors.append(DeskLocalization.source("LOC_A_COMPETITION_LINEAGE_MUST_ORIGINATE_FROM_THE_76CFFF89"))
	if errors.is_empty(): errors.append_array(_validate_variant_compositions(data.variants, variant_ids))
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
			if not family.owner is String or variant.owned != (str(family.owner) == "player"): errors.append(DeskLocalization.source("LOC_AUTHOR_OWNERSHIP_DOES_NOT_MATCH_THE_ACTUAL_4ADFAFF9"))
			if not _number(variant.semantic_distance) or float(variant.semantic_distance) < 0.0 or float(variant.semantic_distance) > 1.0: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_SEMANTIC_DRIFT_8C39ABE4"))
			if str(variant.creator) != "player":
				if variant.parent_ids.is_empty():
					if not variant.origin_ids.is_empty() or variant.owned: errors.append(DeskLocalization.source("LOC_AN_INDEPENDENT_EXTERNAL_VERSION_CANNOT_CLAIM_PLAYER_CB14A8E0"))
				else:
					var parent: Dictionary = variant_ids[variant.parent_ids[0]]
					if competition._canonical(variant.origin_ids) != competition._canonical(parent.origin_ids): errors.append(DeskLocalization.source("LOC_MUTATIONS_MUST_RETAIN_THE_ACTUAL_ORIGINAL_DEPLOYMENT_DD642E47"))
					var meaning_changed: bool = str(variant.meaning_id) != str(parent.meaning_id)
					var split: bool = meaning_changed and float(variant.semantic_distance) >= float(data.families[parent.family_id].split_threshold)
					if not meaning_changed and float(variant.semantic_distance) != 0.0: errors.append("Unchanged meaning cannot claim semantic drift")
					if split != (str(variant.family_id) != str(parent.family_id)) or bool(variant.owned) != (bool(parent.owned) and not split): errors.append(DeskLocalization.source("LOC_MUTATION_OWNERSHIP_CONFLICTS_WITH_THE_FIXED_FAMILY_6809C659"))
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
				if competition._canonical(source_checker.inherited_profile(variant,parent_id)) != competition._canonical(entry.profile): errors.append(DeskLocalization.source("LOC_EXTERNAL_TRANSMISSION_EXPRESSION_DOES_NOT_MATCH_ITS_121705CA"))
			if str(variant.get("source_event","")) != "":
				var found := false
				for event: Dictionary in data.events:
					if str(event.instance_id) == str(variant.source_event) and str(variant.id) in event.get("competition_variant_ids",[]): found = true
				if not found: errors.append(DeskLocalization.source("LOC_COMPETITION_EMERGENCE_EVENT_SOURCE_IS_MISSING_98B83A6B"))
		for event: Dictionary in data.events:
			for id in event.get("competition_variant_ids",[]):
				if not variant_ids.has(id) or str(variant_ids[id].get("source_event","")) != str(event.instance_id): errors.append(DeskLocalization.source("LOC_INVALID_EVENT_COMPETITION_VERSION_REFERENCE_D6AAF201"))
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
	for value in data.event_counts.values():
		if not _number(value) or value < 0: errors.append(DeskLocalization.source("LOC_INVALID_SAVED_EVENT_COUNT_2C1B6BFB"))
	for value in data.last_event_hours.values():
		if not _number(value): errors.append(DeskLocalization.source("LOC_INVALID_SAVED_EVENT_TIME_61D60A84"))
	if errors.is_empty() and not design_state.author_marks_valid(data.latest_draft, data.design_state): errors.append(DeskLocalization.source("LOC_CURRENT_DRAFT_EXPRESSION_PATCH_OR_ABILITY_PROVENANCE_F36FC5F9"))
	if errors.is_empty(): errors.append_array(_validate_guidance_progress(data))
	if errors.is_empty(): data.latest_draft = restored_draft
	return errors

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
			if not variant.patch_ids.is_empty() or preset == null or str(variant.text) != " / ".join(preset.default_values) or variant.has("flow_draft"):
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
		if str(variant.creator) == "player":
			if variant.patch_ids != MutationRules.authored_patch_ids(draft) or (draft.has("patch_ids") and draft.patch_ids != variant.patch_ids):
				return PackedStringArray(["Player expression patches must match the author record"])
			composed = ExpressionText.compose(catalog, draft)
		else:
			if variant.parent_ids.size() != 1:
				return PackedStringArray(["A mutation must have one source version"])
			var parent: Dictionary = variants_by_id[variant.parent_ids[0]]
			var inherited: Array = parent.patch_ids
			if not parent.get("flow_draft") is Dictionary or variant.patch_ids.size() != inherited.size() + 1 or variant.patch_ids.slice(0, inherited.size()) != inherited:
				return PackedStringArray(["A mutation must preserve its parent's patches and add one patch"])
			if parent.flow_draft.get("reuse_permission", "unknown") == "restricted":
				return PackedStringArray(["A restricted source version cannot produce a community rewrite"])
			var mutation := MutationRules.derive(catalog, parent, str(variant.patch_ids.back()))
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
	var actual := JSON.stringify(JSON.parse_string(JSON.stringify(event.design_rewards)), "", true, true)
	var expected := JSON.stringify(JSON.parse_string(JSON.stringify(definition.design_rewards)), "", true, true)
	# An empty delivery is checked against the unique-card history below.
	if (actual != expected and not event.design_rewards.is_empty()) or event.design_source_preset_id != str(definition.external_preset_id): errors.append(DeskLocalization.source("LOC_EVENT_SUPPLY_OR_PRESET_SOURCE_CONFLICTS_WITH_2FE2F3F5"))
	var expected_text: String = ((DeskLocalization.source("LOC_CLAIMED_9C9021A0") if event.acknowledged else DeskLocalization.source("LOC_CLAIM_AFTER_COLLECTING_008ABC0C")) + simulation._reward_summary(event.design_rewards)) if not event.design_rewards.is_empty() else ""
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
	if not progress is Dictionary or progress.size() > 3: return invalid
	for id: Variant in progress:
		if id not in ["fax","competition","mutation"]: return invalid
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
