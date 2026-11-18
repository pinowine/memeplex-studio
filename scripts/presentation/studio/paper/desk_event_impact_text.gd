extends RefCounted

const CardCopy = preload("res://scripts/presentation/studio/paper/desk_material_card_copy.gd")
const Identity = preload("res://scripts/presentation/memes/meme_identity.gd")

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

const COHORTS := {
	"freedom_equality":"LOC_EVENT_COHORT_FREEDOM_EQUALITY",
	"freedom_hierarchy":"LOC_EVENT_COHORT_FREEDOM_HIERARCHY",
	"authority_equality":"LOC_EVENT_COHORT_AUTHORITY_EQUALITY",
	"authority_hierarchy":"LOC_EVENT_COHORT_AUTHORITY_HIERARCHY"
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
	if not response.is_empty(): _append_response(segments, response, record, catalog)
	var created := {"remix":0, "independent":0}
	var produced: Array[Dictionary] = []
	for variant: Dictionary in variants:
		if str(variant.id) in record.competition_variant_ids:
			created["independent" if variant.parent_ids.is_empty() else "remix"] += 1
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
		match kind:
			"attention", "channel_reach", "trust", "fatigue", "revival":
				var amount: float = -float(effect.amount) if kind == "fatigue" else float(effect.amount)
				clause.append(_amount(" " + _signed((maxf(0.05, 1.0 + amount) - 1.0) * 100.0) + "%"))
				clause.append(_duration(float(effect.duration_hours)))
			"adoption":
				clause.append(_amount(" " + _signed(effect.amount * 100.0) + "%"))
			"semantic_shift":
				clause.append(_amount(" = " + _number(effect.amount * 100.0) + "%"))
			"deviation":
				clause.append(_amount(" " + _signed(effect.amount * 100.0) + "%"))
			"remix":
				clause.append(_amount(" +%d" % int(created.remix)))
		_append_clause(segments, clause, "variants" if kind == "remix" else "effects")
	for variant: Dictionary in produced:
		var kind := "INDEPENDENT" if variant.parent_ids.is_empty() else "REMIX"
		_append_clause(segments, [_field("LOC_EVENT_IMPACT_" + kind, "LOC_EVENT_IMPACT_" + kind + "_HELP", "meme", "LOC_EVENT_NOTE_" + kind), _meme_text(str(variant.id), Identity.name(catalog, variant))], "variants")
	for reward: Dictionary in record.design_rewards:
		var entry: Dictionary = catalog.DESIGN_RULES.reward_resource(str(reward.kind), str(reward.id))
		var description := str(entry.get("hover_description", CardCopy.hover_description(str(reward.id))))
		var note := str(entry.get("hover_note", CardCopy.hover_note(str(reward.id))))
		_append_clause(segments, [_field("LOC_EVENT_REWARD_KIND_" + str(reward.kind).to_upper(), "LOC_EVENT_REWARD_MATERIAL_HELP", str(reward.kind), ""),
			_field(str(entry.title), description, str(reward.kind), note), _amount(" ×%d" % int(reward.count))], "rewards")
	return segments

static func _append_response(segments: Array[Dictionary], response: Dictionary, record: Dictionary, catalog: MemeDemoCatalog) -> void:
	var topics: Array[Dictionary] = [_field("LOC_EVENT_RESPONSE_RELATED_TOPICS", "LOC_EVENT_RESPONSE_RELATED_TOPICS_HELP", "topic", "")]
	for topic_id: String in response.topic_ids:
		var id := "topic_" + topic_id
		var topic: Dictionary = catalog.DESIGN_RULES.context_resource(id)
		if topics.size() > 1: topics.append(_text("  "))
		topics.append(_field(str(topic.title), str(topic.get("hover_description", CardCopy.hover_description(id))), "topic", str(topic.get("hover_note", CardCopy.hover_note(id)))))
	if topics.size() > 1: _append_clause(segments, topics, "scope")
	for metric: String in ["attention", "spread", "production"]:
		var amount := float(response[metric])
		if is_zero_approx(amount): continue
		var changes: Array[Dictionary] = [_field("LOC_EVENT_RESPONSE_" + metric.to_upper(), "LOC_EVENT_RESPONSE_" + metric.to_upper() + "_HELP", "metric", ""),
			_amount(_signed(amount * 100.0) + "%"), _duration(float(record.response_duration_hours))]
		_append_clause(segments, changes, "effects")
	var sentiment := float(response.sentiment)
	if not is_zero_approx(sentiment):
		_append_clause(segments, [_text("LOC_EVENT_RESPONSE_EXPRESSION_PREFERENCE"), _expression(sentiment), _text("LOC_EVENT_RESPONSE_PREFERRED")], "audience")
	var dissent: Dictionary = {}
	for cohort: Dictionary in response.cohorts:
		if is_zero_approx(float(cohort.share)): continue
		if float(cohort.sentiment) * sentiment >= 0.0: continue
		if dissent.is_empty() or float(cohort.sentiment) * sentiment < float(dissent.sentiment) * sentiment: dissent = cohort
	if not dissent.is_empty():
		var clause: Array[Dictionary] = [_field(str(COHORTS[str(dissent.id)]), "LOC_EVENT_RESPONSE_COHORT_HELP", "group", ""),
			_text(DeskLocalization.source_format("LOC_EVENT_RESPONSE_POPULATION_SHARE", _number(float(dissent.share) * 100.0))), _text(" "),
			_expression(float(dissent.sentiment)), _text("LOC_EVENT_RESPONSE_PREFERRED")]
		if float(dissent.irony) >= 0.15:
			clause.append(_text("  "))
			clause.append(_field("LOC_EVENT_RESPONSE_IRONY", "LOC_EVENT_RESPONSE_IRONY_HELP", "pragmatic_token", ""))
			clause.append(_text(" " + _number(float(dissent.irony) * 100.0) + "%"))
		_append_clause(segments, clause, "audience")
	elif float(response.irony) >= 0.15:
		_append_clause(segments, [_field("LOC_EVENT_RESPONSE_IRONY", "LOC_EVENT_RESPONSE_IRONY_HELP", "pragmatic_token", ""), _amount(" " + _number(float(response.irony) * 100.0) + "%")], "audience")

static func _groups(ids: PackedStringArray, catalog: MemeDemoCatalog) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	if ids.is_empty():
		segments.append(_field("LOC_EVENT_RESPONSE_LOCAL_AUDIENCE", "LOC_EVENT_RESPONSE_LOCAL_AUDIENCE_HELP", "group", ""))
	else:
		for id: String in ids:
			if not segments.is_empty(): segments.append(_text("  "))
			var group: Dictionary = catalog.DESIGN_RULES.context_resource("group_" + id)
			segments.append(_field(str(group.title), str(group.get("hover_description", CardCopy.hover_description("group_" + id))), "group", str(group.get("hover_note", CardCopy.hover_note("group_" + id)))))
	return segments

static func _append_clause(segments: Array[Dictionary], clause: Array[Dictionary], group: String) -> void:
	if not segments.is_empty(): segments.append({"text":"\n", "impact_group":group})
	for index in clause.size():
		clause[index]["impact_group"] = group
		clause[index]["impact_role"] = "label" if index == 0 else str(clause[index].get("impact_role", "value"))
		segments.append(clause[index])
		if index == 0:
			var gap := _text("  ")
			gap["impact_role"] = "value"
			gap["impact_group"] = group
			segments.append(gap)

static func _amount(value: String) -> Dictionary:
	return {"text":value, "impact_role":"amount"}

static func _duration(hours: float) -> Dictionary:
	return {"text":DeskLocalization.source_format("LOC_EVENT_IMPACT_DURATION", _number(hours)), "impact_role":"duration"}

static func _expression(sentiment: float) -> Dictionary:
	var id := "support" if sentiment > 0.0 else "opposition"
	var title := "LOC_EVENT_RESPONSE_POSITIVE_TERM" if sentiment > 0.0 else "LOC_EVENT_RESPONSE_NEGATIVE_TERM"
	return _field(title, CardCopy.hover_description(id), "pragmatic_token", CardCopy.hover_note(id))

static func _field(title: String, body: String, kind: String, note: String) -> Dictionary:
	return {"text":title, "tooltip_title":title, "tooltip_body":body, "tooltip_note":note, "field_kind":kind}

static func _text(value: String) -> Dictionary:
	return {"text":value}

static func _meme_text(id: String, value: String) -> Dictionary:
	return {"text":"  " + value, "variant_id":id, "field_kind":"meme"}

static func _number(value: float) -> String:
	return ("%.3f" % value).trim_suffix("000").trim_suffix("00").trim_suffix("0").trim_suffix(".")

static func _signed(value: float) -> String:
	return ("+" if value >= 0.0 else "") + _number(value)
