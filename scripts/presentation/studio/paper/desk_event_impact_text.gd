extends RefCounted

const CardCopy = preload("res://scripts/presentation/studio/paper/desk_material_card_copy.gd")
const Identity = preload("res://scripts/presentation/memes/meme_identity.gd")
const MEDIUM_IMPACT := 0.10
const STRONG_IMPACT := 0.20

const METRICS := {
	"attention":["LOC_EVENT_IMPACT_ATTRACTION", "LOC_EVENT_IMPACT_ATTRACTION_HELP", "LOC_EVENT_NOTE_ATTRACTION"],
	"channel_reach":["LOC_EVENT_IMPACT_REACH", "LOC_EVENT_IMPACT_REACH_HELP", "LOC_EVENT_NOTE_REACH"],
	"trust":["LOC_EVENT_RESPONSE_TRUST_EFFECT", "LOC_EVENT_RESPONSE_TRUST_EFFECT_HELP", ""],
	"fatigue":["LOC_EVENT_RESPONSE_FATIGUE_EFFECT", "LOC_EVENT_RESPONSE_FATIGUE_EFFECT_HELP", ""],
	"revival":["LOC_EVENT_RESPONSE_REVIVAL_EFFECT", "LOC_EVENT_RESPONSE_REVIVAL_EFFECT_HELP", ""],
	"adoption":["LOC_EVENT_IMPACT_ADOPTION", "LOC_EVENT_IMPACT_ADOPTION_HELP", "LOC_EVENT_NOTE_ADOPTION"],
	"remix":["LOC_EVENT_IMPACT_REMIX", "LOC_EVENT_IMPACT_REMIX_HELP", "LOC_EVENT_NOTE_REMIX"],
	"semantic_shift":["LOC_EVENT_IMPACT_DRIFT", "LOC_EVENT_IMPACT_DRIFT_HELP", "LOC_EVENT_NOTE_DRIFT"],
	"deviation":["MM_DEVIATION", "MM_HELP_DEVIATION", ""]
}

static func build(record: Dictionary, catalog: MemeDemoCatalog, variants: Array) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	if record.is_empty(): return segments
	if not str(record.get("target_variant_id", "")).is_empty():
		var name := str(record.target_variant_text)
		for variant: Dictionary in variants:
			if str(variant.id) == str(record.target_variant_id):
				name = Identity.name(catalog, variant)
				break
		_append_clause(segments, [_field("LOC_EVENT_RESPONSE_TARGET", "LOC_EVENT_RESPONSE_TARGET_HELP", "meme", ""), _meme_text(str(record.target_variant_id), name)], "scope")
	var response: Dictionary = record.get("response", {})
	if not response.is_empty(): _append_response(segments, response, catalog)
	var produced: Array[Dictionary] = []
	for variant: Dictionary in variants:
		if str(variant.id) in record.competition_variant_ids:
			produced.append(variant)
	for effect: Dictionary in record.get("applied_effects", []):
		var kind := str(effect.effect_id)
		var clause: Array[Dictionary] = []
		var metric: Array = METRICS[kind]
		var help := str(metric[1])
		if kind in ["attention", "channel_reach"]:
			var topics := PackedStringArray()
			for topic_id: String in response.topic_ids:
				topics.append(str(catalog.DESIGN_RULES.context_resource("topic_" + topic_id).title))
			help = DeskLocalization.source_format("LOC_EVENT_IMPACT_TOPIC_HELP", [help, DeskLocalization.source_join("LOC_EVENT_IMPACT_LIST_SEPARATOR", topics)], [0, 1])
		clause.append(_field(str(metric[0]), help, "metric", str(metric[2])))
		if kind in ["attention", "channel_reach", "trust", "fatigue", "revival"]:
			clause.append_array(_groups(PackedStringArray(effect.group_ids), catalog))
		var amount := float(effect.amount)
		if is_zero_approx(amount): continue
		if clause.size() > 1: clause.append(_text("  "))
		clause.append(_impact_arrows(amount))
		_append_clause(segments, clause, "effects")
	for variant: Dictionary in produced:
		var kind := "INDEPENDENT" if variant.parent_ids.is_empty() else "REMIX"
		_append_clause(segments, [_field("LOC_EVENT_IMPACT_" + kind, "LOC_EVENT_IMPACT_" + kind + "_HELP", "meme", "LOC_EVENT_NOTE_" + kind), _meme_text(str(variant.id), Identity.name(catalog, variant))], "variants")
	return segments

static func tendencies(response: Dictionary, country: Dictionary) -> Array[Dictionary]:
	if response.is_empty(): return []
	var stance := _point(country.stance)
	var pragmatic := _point(country.pragmatic)
	var reaction_stance := Vector2.ZERO
	var reaction_tone := Vector2.ZERO
	var weight_total := 0.0
	# Show the profile of the people reacting most strongly, not a permanent country change.
	for cohort: Dictionary in response.cohorts:
		var weight := float(cohort.share) * absf(float(cohort.sentiment))
		reaction_stance += _point(cohort.stance) * weight
		reaction_tone += _point(cohort.pragmatic) * weight
		weight_total += weight
	return [
		{"kind":"stance", "from":stance, "to":reaction_stance / weight_total if weight_total > 0.0 else stance},
		{"kind":"pragmatic", "from":pragmatic, "to":reaction_tone / weight_total if weight_total > 0.0 else pragmatic}
	]

static func reward_previews(record: Dictionary, catalog: MemeDemoCatalog) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for reward: Dictionary in record.get("design_rewards", []):
		var kind := str(reward.kind)
		var entry: Dictionary = catalog.DESIGN_RULES.reward_resource(kind, str(reward.id)).duplicate(true)
		entry.merge({"id":str(reward.id), "kind":kind, "count":int(reward.count),
			"source_label":str(record.title), "received":bool(record.get("acknowledged", false))}, true)
		rows.append(entry)
	return rows

static func _point(pair: Array) -> Vector2:
	return Vector2(float(pair[0]), float(pair[1]))

static func _append_response(segments: Array[Dictionary], response: Dictionary, catalog: MemeDemoCatalog) -> void:
	var topics: Array[Dictionary] = [_field("LOC_EVENT_RESPONSE_RELATED_TOPICS", "LOC_EVENT_RESPONSE_RELATED_TOPICS_HELP", "topic", "")]
	for topic_id: String in response.topic_ids:
		var id := "topic_" + topic_id
		var topic: Dictionary = catalog.DESIGN_RULES.context_resource(id)
		if topics.size() > 1: topics.append(_text("  "))
		topics.append(_resource_field(topic, "topic"))
	if topics.size() > 1: _append_clause(segments, topics, "scope")
	for metric: String in ["attention", "spread", "production"]:
		var amount := float(response[metric])
		if is_zero_approx(amount): continue
		var changes: Array[Dictionary] = [_field("LOC_EVENT_RESPONSE_" + metric.to_upper(), "LOC_EVENT_RESPONSE_" + metric.to_upper() + "_HELP", "metric", ""), _impact_arrows(amount)]
		_append_clause(segments, changes, "effects")

static func _impact_arrows(amount: float) -> Dictionary:
	var direction := 1 if amount > 0.0 else -1
	var magnitude := absf(amount)
	var count := 1 + int(magnitude >= MEDIUM_IMPACT) + int(magnitude >= STRONG_IMPACT)
	return {"text":("↑" if direction > 0 else "↓").repeat(count), "impact_direction":direction}

static func _groups(ids: PackedStringArray, catalog: MemeDemoCatalog) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	if ids.is_empty():
		segments.append(_field("LOC_EVENT_RESPONSE_LOCAL_AUDIENCE", "LOC_EVENT_RESPONSE_LOCAL_AUDIENCE_HELP", "group", ""))
	else:
		for id: String in ids:
			if not segments.is_empty(): segments.append(_text("  "))
			var group: Dictionary = catalog.DESIGN_RULES.context_resource("group_" + id)
			segments.append(_resource_field(group, "group"))
	return segments

static func _append_clause(segments: Array[Dictionary], clause: Array[Dictionary], group: String) -> void:
	if not segments.is_empty(): segments.append({"text":"\n", "impact_group":group})
	for index in clause.size():
		clause[index]["impact_group"] = group
		clause[index]["impact_role"] = "label" if index == 0 else str(clause[index].get("impact_role", "value"))
		segments.append(clause[index])
		if index == 0 and clause.size() > 1:
			var gap := _text("  ")
			gap["impact_role"] = "value"
			gap["impact_group"] = group
			segments.append(gap)

static func _resource_field(entry: Dictionary, kind: String, title: String = "") -> Dictionary:
	var id := str(entry.id)
	var field := _field(str(entry.title) if title.is_empty() else title, str(entry.get("hover_description", CardCopy.hover_description(id))), kind, str(entry.get("hover_note", CardCopy.hover_note(id))))
	field.tooltip_title = str(entry.title)
	field.resource_id = id
	return field

static func _field(title: String, body: String, kind: String, note: String) -> Dictionary:
	return {"text":title, "tooltip_title":title, "tooltip_body":body, "tooltip_note":note, "field_kind":kind}

static func _text(value: String) -> Dictionary:
	return {"text":value}

static func _meme_text(id: String, value: String) -> Dictionary:
	return {"text":"  " + value, "variant_id":id, "field_kind":"meme"}
