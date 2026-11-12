extends RefCounted

const MutationRules = preload("res://scripts/gameplay/events/mutation_rules.gd")
const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")
const Composition = preload("res://scripts/gameplay/design/meme_composition.gd")

static func candidate(catalog: MemeDemoCatalog, parent: Dictionary, definition: MemeDemoEvent) -> Dictionary:
	if not parent.get("flow_draft") is Dictionary: return {}
	if definition.mutation_kind == &"expression": return derive(catalog, parent, "", definition)
	var roles: Array = ["module_relation", "module_shared_world"] if definition.mutation_kind == &"confluence" else ["module_stance", "module_relation", "module_boundary", "module_shared_world", "module_ritual"]
	for role: String in roles:
		for module: Dictionary in catalog.DESIGN_RULES.modules:
			if str(module.get("composition_role", module.id)) != role: continue
			var result := derive(catalog, parent, str(module.id), definition)
			if not result.is_empty(): return result
	return {}

static func derive(catalog: MemeDemoCatalog, parent: Dictionary, patch_id: String, definition: MemeDemoEvent) -> Dictionary:
	if definition.mutation_kind == &"expression":
		if not patch_id.is_empty(): return {}
		return _rewrite_expression(catalog, parent, definition)
	if patch_id.is_empty(): return {}
	var result := MutationRules.derive(catalog, parent, patch_id)
	if result.is_empty(): return {}
	var draft: Dictionary = result.flow_draft
	var bounds: Dictionary = Composition.definition(str(parent.preset_id)).meaning_bounds
	for entry: Array in [["political_position", definition.mutation_stance_delta], ["pragmatic_position", definition.mutation_pragmatic_delta]]:
		var field := str(entry[0])
		var delta: Vector2 = entry[1]
		var position := _position(draft[field]) + delta
		var limits: Array = bounds[field]
		draft[field] = [clampf(position.x, float(limits[0]), float(limits[1])), clampf(position.y, float(limits[2]), float(limits[3]))]
	if definition.mutation_kind == &"confluence":
		var topics: Array = draft.topic_ids.duplicate()
		for topic: String in definition.mutation_topic_ids:
			if topic not in topics: topics.append(topic)
		if topics.size() == draft.topic_ids.size(): return {}
		draft.topic_ids = topics
	if not Composition.validate(draft, result.patch_ids).is_empty(): return {}
	var composed := ExpressionText.compose(catalog, draft)
	if str(composed.meaning_id) == str(parent.meaning_id) or str(composed.meaning) == str(parent.meaning): return {}
	result.composition = composed
	result.meaning_changed = true
	return result

static func _rewrite_expression(catalog: MemeDemoCatalog, parent: Dictionary, definition: MemeDemoEvent) -> Dictionary:
	var draft: Dictionary = parent.flow_draft.duplicate(true)
	draft.slots = ExpressionText.base_slots(draft)
	# A new phrasing keeps the inherited message and releases the author's inventory claims.
	for mark: Dictionary in draft.get("skill_effects", []):
		for effect: Dictionary in mark.get("effects", []):
			draft[str(effect.field)] = clampf(float(draft[str(effect.field)]) - float(effect.delta), 0.0, 1.0)
	for field: String in ["module_patch_record", "skill_effects", "context_layer_record"]: draft.erase(field)
	draft.patch_ids = parent.patch_ids.duplicate()
	if definition.mutation_expression_mode == &"translation":
		var current := Composition.LANGUAGES.find(str(draft.language_id))
		draft.language_id = str(Composition.LANGUAGES[(current + 1) % Composition.LANGUAGES.size()])
		draft.language_ids = [draft.language_id]
	if not Composition.validate(draft, draft.patch_ids).is_empty(): return {}
	var composed := ExpressionText.compose(catalog, draft)
	if definition.mutation_expression_mode == &"rephrase":
		composed.expression = str(composed.meaning)
		composed.expression_segments = composed.meaning_segments.duplicate(true)
		for version: Dictionary in composed.language_versions: version.expression = str(composed.meaning)
	if str(composed.expression) == str(parent.text) or str(composed.meaning_id) != str(parent.meaning_id): return {}
	return {"patch_id":"", "patch_ids":draft.patch_ids.duplicate(), "flow_draft":draft, "composition":composed, "meaning_changed":false}

static func _position(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]), float(value[1]))

static func merge_with(result: Dictionary, companion: Dictionary) -> Dictionary:
	var merged := result.duplicate(true)
	var composed: Dictionary = merged.composition
	var companion_meaning := str(companion.get("meaning", companion.text))
	if companion_meaning.is_empty(): companion_meaning = str(companion.text)
	var identity := "\n".join([str(composed.meaning_id), str(composed.meaning), companion_meaning, str(companion.text)])
	composed.meaning_id = str(composed.meaning_id) + "/confluence:" + identity.sha256_text()
	composed.expression = DeskLocalization.source_join(" / ", [str(composed.expression), str(companion.text)])
	composed.meaning = DeskLocalization.source_join(" / ", [str(composed.meaning), companion_meaning])
	composed.expression_segments.append({"text":" / ", "sources":[]})
	composed.expression_segments.append({"text":str(companion.text), "sources":[]})
	composed.meaning_segments.append({"text":" / ", "sources":[]})
	composed.meaning_segments.append({"text":companion_meaning, "sources":[]})
	for version: Dictionary in composed.language_versions: version.expression = str(composed.expression)
	merged.meaning_changed = true
	merged.companion_id = str(companion.id)
	return merged
