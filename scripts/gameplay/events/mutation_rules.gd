extends RefCounted

const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")

static func authored_patch_ids(draft: Dictionary) -> Array:
	var result: Array = []
	for id: String in draft.get("module_patch_record", {}).get("modules", []):
		if not id.is_empty(): result.append(id)
	return result

static func patch_ids(draft: Dictionary) -> Array:
	return draft.patch_ids.duplicate() if draft.has("patch_ids") else authored_patch_ids(draft)

static func candidate(catalog: MemeDemoCatalog, parent: Dictionary, event_definition_id: String = "") -> Dictionary:
	if not parent.get("flow_draft") is Dictionary: return {}
	var inherited: Array = parent.patch_ids
	if inherited.size() >= catalog.DESIGN_RULES.module_slots: return {}
	var preferred: String = {"semantic_split":"module_stance", "critical_quote":"module_stance", "cross_language":"module_boundary", "platform_tool":"module_shared_world"}.get(event_definition_id, "")
	var candidates: Array[String] = []
	if not preferred.is_empty(): candidates.append(str(catalog.DESIGN_RULES.find("modules",preferred).id))
	for module: Dictionary in catalog.DESIGN_RULES.modules:
		if str(module.id) not in candidates: candidates.append(str(module.id))
	for id: String in candidates:
		var result := derive(catalog, parent, id)
		if not result.is_empty(): return result
	return {}

static func derive(catalog: MemeDemoCatalog, parent: Dictionary, patch_id: String) -> Dictionary:
	var ids: Array = parent.patch_ids.duplicate()
	ids.append(patch_id)
	if not catalog.DESIGN_RULES.patch_errors(str(parent.preset_id), ids).is_empty(): return {}
	var draft: Dictionary = parent.flow_draft.duplicate(true)
	draft.slots = ExpressionText.base_slots(draft)
	# A community inherits the expression without claiming the author's inventory records.
	for mark: Dictionary in draft.get("skill_effects", []):
		for effect: Dictionary in mark.get("effects", []):
			draft[str(effect.field)] = clampf(float(draft[str(effect.field)]) - float(effect.delta), 0.0, 1.0)
	for field: String in ["module_patch_record", "skill_effects", "context_layer_record"]:
		draft.erase(field)
	draft.patch_ids = ids.duplicate()
	var module: Dictionary = catalog.DESIGN_RULES.find("modules", patch_id)
	for effect: Dictionary in module.draft_effects:
		var field := str(effect.field)
		draft[field] = clampf(float(draft[field]) + float(effect.amount), 0.0, 1.0)
	var composed: Dictionary = ExpressionText.compose(catalog, draft)
	if str(composed.get("expression", "")).is_empty(): return {}
	if str(composed.expression) == str(parent.text) and str(composed.meaning_id) == str(parent.meaning_id): return {}
	return {"patch_id":patch_id, "patch_ids":ids, "flow_draft":draft, "composition":composed, "meaning_changed":str(composed.meaning_id) != str(parent.meaning_id)}
