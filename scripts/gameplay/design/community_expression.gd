extends RefCounted

const Composition = preload("res://scripts/gameplay/design/meme_composition.gd")

static func inherited_draft(parent: Dictionary) -> Dictionary:
	var draft: Dictionary = parent.flow_draft.duplicate(true)
	if not draft.has("community_rephrase"):
		var shortened := Composition.rephrase_expression(effective_draft(draft), parent.patch_ids)
		if str(shortened.get("expression", "")) == str(parent.text): draft.community_rephrase = true
	return draft

static func change(raw: Dictionary) -> Dictionary:
	var before: Dictionary = raw.mutation_parent_content
	var previous: Dictionary = before.flow_draft
	var current: Dictionary = raw.flow_draft
	var patches: Array = []
	for id: String in raw.patch_ids:
		if id not in before.patch_ids: patches.append(id)
	var delta := {"source_id":str(raw.id), "patch_ids":patches, "topics":[], "axes":{}, "scalars":{}, "language_id":"", "rephrase":bool(current.get("community_rephrase", false)) and not bool(previous.get("community_rephrase", false)), "confluence":[]}
	if not current.has("community_rephrase") and str(raw.meaning_id) == str(before.meaning_id) and str(raw.text) != str(before.text) and current.language_id == previous.language_id: delta.rephrase = true
	for field: String in ["language_access", "recognizability", "context_dependency", "remix_cost"]:
		var baseline := float(previous[field])
		for mark: Dictionary in previous.get("skill_effects", []):
			for effect: Dictionary in mark.get("effects", []):
				if str(effect.field) == field: baseline = clampf(baseline - float(effect.delta), 0.0, 1.0)
		var amount := float(current[field]) - baseline
		if not is_zero_approx(amount): delta.scalars[field] = amount
	for field: String in ["political_position", "pragmatic_position"]:
		var a: Vector2 = _point(previous[field])
		var b: Vector2 = _point(current[field])
		if not a.is_equal_approx(b): delta.axes[field] = [b.x-a.x, b.y-a.y]
	for id: String in current.topic_ids:
		if id not in previous.topic_ids: delta.topics.append(id)
	if current.language_id != previous.language_id: delta.language_id = str(current.language_id)
	if raw.has("confluence_companion_content"):
		var companion: Dictionary = raw.confluence_companion_content
		delta.confluence.append({"text":str(companion.text), "meaning":str(companion.get("meaning", companion.text))})
	return delta

static func collect(base: Array, active: Dictionary, variants: Array) -> Array:
	var result: Array = base.duplicate(true)
	var cursor := active
	var pending: Array = []
	if active.has("rollback_from_id"): return active.effective_content.flow_draft.get("community_changes", []).duplicate(true)
	while not cursor.is_empty() and str(cursor.creator) != "player" and not cursor.get("parent_ids", []).is_empty():
		pending.push_front(change(cursor))
		var parent_id := str(cursor.parent_ids[0])
		cursor = {}
		for raw: Dictionary in variants:
			if str(raw.id) == parent_id: cursor = raw; break
	for delta: Dictionary in pending:
		if not result.any(func(existing: Dictionary): return existing.source_id == delta.source_id): result.append(delta)
	return result

static func patch_ids(draft: Dictionary, authored: Array) -> Array:
	var result := authored.duplicate()
	for delta: Dictionary in draft.get("community_changes", []):
		for id: String in delta.patch_ids:
			if id not in result: result.append(id)
	return result

static func effective_draft(draft: Dictionary) -> Dictionary:
	var effective := draft.duplicate(true)
	if draft.get("community_changes", []).is_empty(): return effective
	var bounds: Dictionary = Composition.definition(str(draft.preset_id)).meaning_bounds
	for delta: Dictionary in draft.get("community_changes", []):
		for field: String in delta.get("scalars", {}): effective[field] = clampf(float(effective[field]) + float(delta.scalars[field]), 0.0, 1.0)
		for field: String in delta.axes:
			var point := _point(effective[field]) + _point(delta.axes[field])
			var limits: Array = bounds[field]
			effective[field] = [clampf(point.x,limits[0],limits[1]),clampf(point.y,limits[2],limits[3])]
		effective.topic_ids = Array(effective.topic_ids)
		for id: String in delta.topics:
			if id not in effective.topic_ids: effective.topic_ids.append(id)
		if not str(delta.language_id).is_empty():
			var languages: Array = Array(effective.get("language_ids", [effective.language_id]))
			if str(delta.language_id) not in languages: languages.append(str(delta.language_id))
			effective.language_ids = languages
	effective.erase("community_changes")
	return effective

static func compose(draft: Dictionary, modules: Array) -> Dictionary:
	var effective := effective_draft(draft)
	var rephrase := bool(draft.get("community_rephrase", false))
	var confluence: Array = draft.get("confluence_contents", []).duplicate(true)
	for delta: Dictionary in draft.get("community_changes", []):
		rephrase = rephrase or bool(delta.rephrase)
		confluence.append_array(delta.confluence)
	var result := Composition.compose(effective, modules)
	if result.is_empty(): return result
	if rephrase:
		var shortened := Composition.rephrase_expression(effective, modules)
		result.expression = str(shortened.expression)
		result.expression_segments = shortened.segments
		for version: Dictionary in result.language_versions: version.expression = str(Composition.rephrase_expression(effective,modules,str(version.language_id)).expression)
	for companion: Dictionary in confluence:
		var companion_meaning := str(companion.meaning)
		if companion_meaning.is_empty(): companion_meaning = str(companion.text)
		var identity := "\n".join([str(result.meaning_id), str(result.meaning), companion_meaning, str(companion.text)])
		result.meaning_id = str(result.meaning_id) + "/confluence:" + identity.sha256_text()
		result.expression = DeskLocalization.source_join(" / ", [str(result.expression), str(companion.text)])
		result.meaning = DeskLocalization.source_join(" / ", [str(result.meaning), companion_meaning])
		result.expression_segments.append({"text":" / ", "sources":[]})
		result.expression_segments.append({"text":str(companion.text), "sources":[]})
		result.meaning_segments.append({"text":" / ", "sources":[]})
		result.meaning_segments.append({"text":companion_meaning, "sources":[]})
		for version: Dictionary in result.language_versions: version.expression = str(result.expression)
	return result

static func _point(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2(float(value[0]),float(value[1]))
