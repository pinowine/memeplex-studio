extends RefCounted

const SPLIT_THRESHOLD := 0.5

static func spread(counts: Dictionary, population: int, attention_budget: int) -> float:
	if population == 0: return 0.0
	var adopted := clampf(float(counts.adopted) / population, 0.0, 1.0)
	var exposed := clampf(float(counts.exposed) / population, 0.0, 1.0)
	var attention := clampf(float(counts.attention) / attention_budget, 0.0, 1.0) if attention_budget > 0 else 0.0
	return (adopted + exposed + attention) / 3.0

static func growth(current: float, previous: float) -> float:
	if previous <= 0.0: return 1.0 if current > 0.0 else 0.0
	return clampf((current - previous) / previous, -1.0, 1.0)

static func initial_variant(variants: Array, variant: Dictionary) -> Dictionary:
	if variant.get("deviation_anchor") is Dictionary: return variant.deviation_anchor
	var by_id := {}
	for item: Dictionary in variants: by_id[str(item.id)] = item
	var initial := variant
	while not initial.get("parent_ids", []).is_empty():
		initial = by_id[str(initial.parent_ids[0])]
	return initial

static func deviation(initial: Dictionary, current: Dictionary) -> float:
	var expression := _text_distance(str(initial.get("text", "")), str(current.get("text", "")))
	var meaning := _text_distance(str(initial.get("meaning", "")), str(current.get("meaning", "")))
	var initial_meaning := str(initial.get("meaning_id", ""))
	var current_meaning := str(current.get("meaning_id", ""))
	if not is_zero_approx(meaning) and (not initial_meaning.is_empty() or not current_meaning.is_empty()):
		meaning = (meaning + (0.0 if initial_meaning == current_meaning else 1.0)) * 0.5
	var before: Dictionary = initial.get("flow_profile", initial.get("flow_draft", {}))
	var after: Dictionary = current.get("flow_profile", current.get("flow_draft", {}))
	var context := _context_distance(before, after)
	# Meaning carries most weight; wording and context distinguish changes within a meaning.
	return clampf(meaning * 0.6 + expression * 0.2 + context * 0.2, 0.0, 1.0)

static func should_split(distance: float) -> bool:
	return distance > SPLIT_THRESHOLD

static func _text_distance(before: String, after: String) -> float:
	if before == after: return 0.0
	return 1.0 - before.similarity(after)

static func _set_distance(before: Array, after: Array) -> float:
	var union := {}
	var shared := 0
	for value: Variant in before: union[value] = true
	for value: Variant in after:
		if value in before: shared += 1
		union[value] = true
	return 0.0 if union.is_empty() else 1.0 - float(shared) / union.size()

static func _axis_distance(before: Variant, after: Variant) -> float:
	return (absf(float(before[0]) - float(after[0])) + absf(float(before[1]) - float(after[1]))) / 4.0

static func _context_distance(before: Dictionary, after: Dictionary) -> float:
	var distance := 0.0
	for layer: String in ["language", "group", "topic"]:
		var key := "topic_ids" if layer == "topic" else layer + "_ids"
		var a: Array = before.get(key, [] if layer == "topic" else [before.get(layer + "_id", "")])
		var b: Array = after.get(key, [] if layer == "topic" else [after.get(layer + "_id", "")])
		distance += _set_distance(a, b)
	var known_before := bool(before.get("political_known", false))
	var known_after := bool(after.get("political_known", false))
	distance += 1.0 if known_before != known_after else (_axis_distance(before.get("political_position", [0.0, 0.0]), after.get("political_position", [0.0, 0.0])) if known_before else 0.0)
	distance += _axis_distance(before.get("pragmatic_position", [0.0, 0.0]), after.get("pragmatic_position", [0.0, 0.0]))
	var attachment := 0.0
	for layer: String in ["language", "group", "topics", "stance", "pragmatic"]:
		if bool(before.get("context_layer_attachment", {}).get(layer, true)) != bool(after.get("context_layer_attachment", {}).get(layer, true)): attachment += 0.2
	return (distance + attachment) / 6.0
