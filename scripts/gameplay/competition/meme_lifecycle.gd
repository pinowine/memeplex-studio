extends RefCounted

const Metrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")
const SEMANTIC_PROFILE_FIELDS := ["language_id", "language_ids", "group_id", "group_ids", "topic_ids", "political_known", "political_position", "pragmatic_position", "context_layer_attachment"]
const PATCH_SCALAR_FIELDS := ["language_access", "recognizability", "context_dependency", "remix_cost"]
const DRAFT_CONTENT_FIELDS := ["slots", "module_patch_record", "community_changes", "community_rephrase", "confluence_contents"]
const CONTENT_FIELDS := ["id", "family_id", "parent_ids", "origin_ids", "creator", "owned", "controlled", "text", "meaning", "meaning_id", "language_versions", "kernel_id", "preset_id", "source_presets", "language_id", "topic_ids", "political_known", "political_position", "pragmatic_position", "context_layer_attachment", "patch_ids", "flow_draft", "flow_profile", "source_event", "mutation_definition_id", "mutation_patch_id", "confluence_source_id", "deviation_effect_deltas", "deviation_patch_effects"]
var _simulation: RefCounted

func _init(simulation: RefCounted) -> void:
	_simulation = simulation

static func content(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	result.merge(raw.get("effective_content", {}), true)
	return result

static func revision_snapshot(raw: Dictionary) -> Dictionary:
	var visible := content(raw)
	var result := {}
	for field: String in CONTENT_FIELDS:
		if visible.has(field): result[field] = visible[field].duplicate(true) if visible[field] is Dictionary or visible[field] is Array else visible[field]
	return result

static func semantic_snapshot(raw: Dictionary) -> Dictionary:
	var visible := content(raw)
	var result := {}
	for field: String in ["text", "meaning", "meaning_id", "language_versions", "patch_ids", "language_id", "topic_ids", "political_known", "political_position", "pragmatic_position", "context_layer_attachment"]:
		if visible.has(field): result[field] = visible[field].duplicate(true) if visible[field] is Dictionary or visible[field] is Array else visible[field]
	for field: String in ["flow_draft", "flow_profile"]:
		var source: Dictionary = visible.get(field, {})
		var semantic := {}
		for key: String in SEMANTIC_PROFILE_FIELDS:
			if source.has(key): semantic[key] = source[key].duplicate(true) if source[key] is Dictionary or source[key] is Array else source[key]
		if source.has("expression"): semantic.expression = source.expression
		if field == "flow_draft":
			for key: String in DRAFT_CONTENT_FIELDS:
				if source.has(key): semantic[key] = source[key].duplicate(true) if source[key] is Dictionary or source[key] is Array else source[key]
		result[field] = semantic
	return result

static func rollback_content(anchor: Dictionary, candidate: Dictionary) -> Dictionary:
	var visible := content(candidate)
	var result := {}
	for field: String in ["text", "meaning", "meaning_id", "language_versions", "patch_ids", "language_id", "topic_ids", "political_known", "political_position", "pragmatic_position", "context_layer_attachment"]:
		if anchor.has(field): result[field] = anchor[field].duplicate(true) if anchor[field] is Dictionary or anchor[field] is Array else anchor[field]
	for field: String in ["flow_draft", "flow_profile"]:
		var profile: Dictionary = visible.get(field, {}).duplicate(true)
		var semantic: Dictionary = anchor.get(field, {})
		for key: String in SEMANTIC_PROFILE_FIELDS:
			if semantic.has(key): profile[key] = semantic[key].duplicate(true) if semantic[key] is Dictionary or semantic[key] is Array else semantic[key]
			else: profile.erase(key)
		if semantic.has("expression"): profile.expression = semantic.expression
		if field == "flow_profile" and anchor.has("text"): profile.text = str(anchor.text)
		if field == "flow_draft":
			for key: String in DRAFT_CONTENT_FIELDS:
				if semantic.has(key): profile[key] = semantic[key].duplicate(true) if semantic[key] is Dictionary or semantic[key] is Array else semantic[key]
				else: profile.erase(key)
			var retained: Array = anchor.get("patch_ids", []).duplicate()
			if ExpressionText.Composition.supports(str(profile.get("preset_id", ""))):
				for patch: String in visible.get("patch_ids", []):
					if patch in retained: continue
					var attempt := retained.duplicate()
					attempt.append(patch)
					var composed := ExpressionText.Community.compose(profile, attempt)
					if not composed.is_empty() and str(composed.expression) == str(anchor.get("text", "")) and str(composed.meaning) == str(anchor.get("meaning", "")): retained.append(patch)
			profile.patch_ids = retained
			result.patch_ids = retained
		result[field] = profile
	var deltas := effect_deltas(anchor, candidate)
	for field: String in PATCH_SCALAR_FIELDS:
		if result.flow_draft.has(field): result.flow_draft[field] = clampf(float(visible.flow_draft[field]) - float(deltas.get(field, 0.0)), 0.0, 1.0)
	if not result.flow_draft.is_empty():
		var calculator: RefCounted = load("res://scripts/gameplay/competition/competition_state.gd").new(load("res://data/catalogs/catalog.tres"))
		var evaluated: Dictionary = calculator.profile(result.flow_draft)
		for field: String in PATCH_SCALAR_FIELDS: result.flow_profile[field] = evaluated[field]
		result.flow_profile.propagation_meta = evaluated.propagation_meta.duplicate(true)
	var before_profile: Dictionary = visible.get("flow_profile", {})
	var reference_profile: Dictionary = anchor.get("flow_profile", {})
	if not bool(reference_profile.get("political_known", false)):
		for field: String in ["flow_draft", "flow_profile"]:
			if visible.get(field, {}).has("political_position"): result[field].political_position = visible[field].political_position.duplicate()
		if visible.has("political_position"): result.political_position = visible.political_position.duplicate()
	result.semantic_distance = 0.0
	return result

static func _record_patch_effects(draft: Dictionary) -> Dictionary:
	var result := {}
	var record: Dictionary = draft.get("module_patch_record", {})
	var offset := 0
	var rules: Resource = load("res://data/rules/design_rules.tres")
	for patch: String in record.get("modules", []):
		if patch.is_empty(): continue
		var values := {}
		for _effect: Dictionary in rules.find("modules", patch).get("draft_effects", []):
			var applied: Dictionary = record.effects[offset]
			offset += 1
			values[str(applied.field)] = float(values.get(str(applied.field), 0.0)) + float(applied.delta)
		result[patch] = values
	return result

static func retained_patches(anchor: Dictionary, candidate: Dictionary) -> Array:
	var visible := content(candidate)
	var draft: Dictionary = visible.get("flow_draft", {}).duplicate(true)
	var semantic: Dictionary = anchor.get("flow_draft", {})
	for key: String in SEMANTIC_PROFILE_FIELDS + DRAFT_CONTENT_FIELDS:
		if semantic.has(key): draft[key] = semantic[key].duplicate(true) if semantic[key] is Dictionary or semantic[key] is Array else semantic[key]
		else: draft.erase(key)
	var retained: Array = anchor.get("patch_ids", []).duplicate()
	if ExpressionText.Composition.supports(str(draft.get("preset_id", ""))):
		for patch: String in visible.get("patch_ids", []):
			if patch in retained: continue
			var attempt := retained.duplicate()
			attempt.append(patch)
			var composed := ExpressionText.Community.compose(draft, attempt)
			if not composed.is_empty() and str(composed.expression) == str(anchor.get("text", "")) and str(composed.meaning) == str(anchor.get("meaning", "")): retained.append(patch)
	return retained

static func patch_effects(anchor: Dictionary, candidate: Dictionary, parent: Dictionary = {}) -> Dictionary:
	if candidate.has("split_patch_effects"): return candidate.split_patch_effects.duplicate(true)
	var draft: Dictionary = candidate.get("flow_draft", {})
	if draft.has("module_patch_record"): return _record_patch_effects(draft)
	var source: Dictionary = candidate.get("mutation_parent_content", parent)
	var result: Dictionary = source.get("deviation_patch_effects", {}).duplicate(true) if not source.is_empty() else candidate.get("deviation_patch_effects", {}).duplicate(true)
	if not source.is_empty():
		var inherited := content(source)
		var added: Array = []
		for patch: String in candidate.get("patch_ids", []):
			if patch not in inherited.get("patch_ids", []): added.append(patch)
		if not added.is_empty():
			var before: Dictionary = inherited.get("flow_draft", {}).duplicate(true)
			for mark: Dictionary in before.get("skill_effects", []):
				for effect: Dictionary in mark.get("effects", []):
					var field := str(effect.field)
					before[field] = clampf(float(before[field]) - float(effect.delta), 0.0, 1.0)
			var values := {}
			for field: String in PATCH_SCALAR_FIELDS: values[field] = float(draft.get(field, 0.0)) - float(before.get(field, 0.0))
			result[str(added[0])] = values
	return result

static func effect_deltas(anchor: Dictionary, candidate: Dictionary, parent: Dictionary = {}) -> Dictionary:
	if candidate.has("split_effect_deltas"): return candidate.split_effect_deltas.duplicate(true)
	var effects := patch_effects(anchor, candidate, parent)
	var retained := retained_patches(anchor, candidate)
	var result := {}
	for patch: String in candidate.get("patch_ids", []):
		if patch in retained: continue
		for field: String in effects.get(patch, {}): result[field] = float(result.get(field, 0.0)) + float(effects[patch][field])
	var original := _record_patch_effects(anchor.get("flow_draft", {}))
	for patch: String in anchor.get("patch_ids", []):
		if patch in candidate.get("patch_ids", []): continue
		for field: String in original.get(patch, {}): result[field] = float(result.get(field, 0.0)) - float(original[patch][field])
	return result

func active_source(raw: Dictionary) -> Dictionary:
	if raw.is_empty(): return {}
	if not bool(raw.get("retired", false)): return raw
	var meme_id := str(raw.get("meme_id", raw.id))
	for index in range(_simulation.variants.size() - 1, -1, -1):
		var candidate: Dictionary = _simulation.variants[index]
		if not bool(candidate.get("retired", false)) and str(candidate.get("meme_id", candidate.id)) == meme_id: return candidate
	return raw

func _initialize_identity(raw: Dictionary, legacy: bool = false) -> void:
	if raw.has("meme_id"): return
	raw.meme_id = str(raw.id)
	if legacy: raw.legacy_identity = true
	raw.meme_name = "MN_" + str(raw.preset_id).to_upper() if not str(raw.get("preset_id", "")).is_empty() else str(raw.text)
	raw.meme_name_index = -1
	raw.deviation_anchor = semantic_snapshot(raw)
	raw.retired = false
	raw.split_distance = 0.0
	raw.deviation_effect_deltas = {}
	raw.deviation_patch_effects = {}

func activate(raw: Dictionary, source: Dictionary = {}) -> Dictionary:
	if source.is_empty():
		_initialize_identity(raw)
		return {"split":false, "new_meme":true, "meme_id":str(raw.meme_id)}
	var parent := active_source(_simulation.variant_by_id(str(source.id)))
	var transfer_error: String = _simulation.competition._transfer_error(str(parent.id), str(raw.id))
	if not transfer_error.is_empty(): return {"error":transfer_error}
	_initialize_identity(raw)
	_initialize_identity(parent, true)
	var reference: Dictionary = parent.deviation_anchor
	raw.deviation_patch_effects = patch_effects(reference, raw, parent)
	raw.deviation_effect_deltas = effect_deltas(reference, raw, parent)
	var distance := Metrics.deviation(reference, content(raw))
	raw.split_distance = distance
	var policy_parent := revision_snapshot(parent)
	policy_parent.flow_profile = _simulation.competition.live_profile(str(parent.id))
	var threshold: float = _simulation.competition.propagation_rules.split_threshold(Metrics.SPLIT_THRESHOLD, policy_parent, {"flow_draft":content(raw).get("flow_draft", {})})
	raw.mutation_policy = {"schema":1, "metric_version":Metrics.DEVIATION_VERSION, "profile_version":_simulation.competition.INHERITED_PROFILE_VERSION, "source_id":str(parent.id), "skill_ids":policy_parent.flow_profile.get("skill_ids", []).duplicate(), "threshold":threshold, "hour":int(_simulation.hour), "ledger_size":_simulation.economy.transactions.size()}
	if distance > threshold and not _simulation.can_add_meme(str(raw.id)):
		return {"error":DeskLocalization.source("LOC_MEME_POOL_FULL")}
	if distance <= threshold:
		raw.meme_id = str(parent.meme_id)
		raw.meme_name = str(parent.meme_name)
		raw.meme_name_index = int(parent.get("meme_name_index", -1))
		if parent.has("split_parent_name"): raw.split_parent_name = str(parent.split_parent_name)
		raw.deviation_anchor = reference.duplicate(true)
		raw.semantic_distance = distance
		var identity := content(parent)
		var effective: Dictionary = raw.get("effective_content", {}).duplicate(true)
		for field: String in ["creator", "owned", "controlled"]: effective[field] = identity[field]
		raw.effective_content = effective
		parent.retired = true
		var transfer: Dictionary = _simulation.competition.replace_revision(str(parent.id), str(raw.id))
		if transfer.has("error"): return transfer
		if str(_simulation.current_variant_id) == str(parent.id): _simulation.current_variant_id = str(raw.id)
		_simulation.attention = _simulation.competition.snapshot(_simulation.variants, false).attention
		return {"split":false, "new_meme":false, "meme_id":str(raw.meme_id), "distance":distance}
	var rolled := rollback_content(reference, raw)
	var identity := content(parent)
	for field: String in ["creator", "owned", "controlled"]: rolled[field] = identity[field]
	if parent.has("effective_content"):
		if not parent.has("effective_history"): parent.effective_history = []
		parent.effective_history.append(revision_snapshot(parent))
	parent.effective_content = rolled
	parent.rollback_from_id = str(raw.id)
	parent.deviation_effect_deltas = {}
	parent.deviation_patch_effects = {}
	parent.erase("split_effect_deltas")
	parent.erase("split_patch_effects")
	raw.split_from_id = str(parent.id)
	raw.split_parent_name = str(parent.get("split_parent_name", parent.meme_name))
	raw.split_effect_deltas = raw.deviation_effect_deltas.duplicate(true)
	raw.split_patch_effects = raw.deviation_patch_effects.duplicate(true)
	raw.deviation_effect_deltas = {}
	raw.deviation_patch_effects = {}
	raw.semantic_distance = 0.0
	if str(raw.creator) != "player": raw.owned = false
	var name_index := 0
	for item: Dictionary in _simulation.variants:
		if item == raw: continue
		name_index = maxi(name_index, int(item.get("meme_name_index", -1)) + 1)
	raw.meme_name_index = name_index
	raw.meme_name = "MEME_SPLIT_NAME_%02d" % (name_index % 16)
	raw.deviation_anchor = semantic_snapshot(raw)
	var allocation: Dictionary = _simulation.competition.split_revision(str(parent.id), str(raw.id), raw.flow_profile, rolled.flow_profile)
	if allocation.has("error"): return allocation
	_simulation.attention = _simulation.competition.snapshot(_simulation.variants, false).attention
	return {"split":true, "new_meme":true, "meme_id":str(raw.meme_id), "distance":distance, "allocation":allocation}
