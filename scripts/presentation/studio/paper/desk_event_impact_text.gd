extends RefCounted

const CardCopy = preload("res://scripts/presentation/studio/paper/desk_material_card_copy.gd")

const METRICS := {
	"attention":["LOC_EVENT_IMPACT_ATTRACTION", "LOC_EVENT_IMPACT_ATTRACTION_HELP", "LOC_EVENT_NOTE_ATTRACTION"],
	"channel_reach":["LOC_EVENT_IMPACT_REACH", "LOC_EVENT_IMPACT_REACH_HELP", "LOC_EVENT_NOTE_REACH"],
	"trust":["LOC_EVENT_RESPONSE_TRUST_EFFECT", "LOC_EVENT_RESPONSE_TRUST_EFFECT_HELP", ""],
	"fatigue":["LOC_EVENT_RESPONSE_FATIGUE_EFFECT", "LOC_EVENT_RESPONSE_FATIGUE_EFFECT_HELP", ""],
	"revival":["LOC_EVENT_RESPONSE_REVIVAL_EFFECT", "LOC_EVENT_RESPONSE_REVIVAL_EFFECT_HELP", ""],
	"adoption":["LOC_EVENT_IMPACT_ADOPTION", "LOC_EVENT_IMPACT_ADOPTION_HELP", "LOC_EVENT_NOTE_ADOPTION"],
	"remix":["LOC_EVENT_IMPACT_REMIX", "LOC_EVENT_IMPACT_REMIX_HELP", "LOC_EVENT_NOTE_REMIX"],
	"semantic_shift":["LOC_EVENT_IMPACT_DRIFT", "LOC_EVENT_IMPACT_DRIFT_HELP", "LOC_EVENT_NOTE_DRIFT"]
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
		_append_clause(segments, [_field("LOC_EVENT_RESPONSE_TARGET", "LOC_EVENT_RESPONSE_TARGET_HELP", "meme", ""), _text("  " + str(record.target_variant_text))])
	var response: Dictionary = record.get("response", {})
	if not response.is_empty(): _append_response(segments, response, record, catalog)
	var created := {"remix":0, "independent":0}
	var independent: Array[Dictionary] = []
	for variant: Dictionary in variants:
		if str(variant.id) in record.competition_variant_ids:
			created["independent" if variant.parent_ids.is_empty() else "remix"] += 1
			if variant.parent_ids.is_empty(): independent.append(variant)
	for effect: Dictionary in record.get("applied_effects", []):
		var kind := str(effect.effect_id)
		var clause: Array[Dictionary] = []
		if kind in ["attention", "channel_reach", "trust", "fatigue", "revival"]:
			clause.append_array(_groups(PackedStringArray(effect.group_ids), catalog))
			clause.append(_text("LOC_EVENT_IMPACT_POSSESSIVE"))
		var metric: Array = METRICS[kind]
		var help := str(metric[1])
		if kind in ["attention", "channel_reach"]:
			var topics := PackedStringArray()
			for topic_id: String in response.topic_ids:
				topics.append(str(catalog.DESIGN_RULES.context_resource("topic_" + topic_id).title))
			help = DeskLocalization.source_format("LOC_EVENT_IMPACT_TOPIC_HELP", [help, DeskLocalization.source_join("LOC_EVENT_IMPACT_LIST_SEPARATOR", topics)], [0, 1])
		clause.append(_field(str(metric[0]), help, "metric", str(metric[2])))
		match kind:
			"attention", "channel_reach", "trust", "fatigue", "revival":
				var amount: float = -float(effect.amount) if kind == "fatigue" else float(effect.amount)
				clause.append(_text(" " + _signed((maxf(0.05, 1.0 + amount) - 1.0) * 100.0) + "%"))
				clause.append(_text(DeskLocalization.source_format("LOC_EVENT_IMPACT_DURATION", _number(float(effect.duration_hours)))))
			"adoption":
				clause.append(_text(" " + _signed(effect.amount * 100.0) + "%"))
			"semantic_shift":
				clause.append(_text(" = " + _number(effect.amount * 100.0) + "%"))
			"remix":
				clause.append(_text(" +%d" % int(created.remix)))
		_append_clause(segments, clause)
	for variant: Dictionary in independent:
		_append_clause(segments, [_field("LOC_EVENT_IMPACT_INDEPENDENT", "LOC_EVENT_IMPACT_INDEPENDENT_HELP", "meme", "LOC_EVENT_NOTE_INDEPENDENT"), _text("  " + str(variant.text))])
	for reward: Dictionary in record.design_rewards:
		var entry: Dictionary = catalog.DESIGN_RULES.reward_resource(str(reward.kind), str(reward.id))
		var description := CardCopy.hover_description(str(reward.id))
		_append_clause(segments, [_field(str(entry.title), description, str(reward.kind), CardCopy.hover_note(str(reward.id))), _text(" +%d" % int(reward.count))])
	return segments

static func _append_response(segments: Array[Dictionary], response: Dictionary, record: Dictionary, catalog: MemeDemoCatalog) -> void:
	var topics := PackedStringArray()
	for topic_id: String in response.topic_ids:
		topics.append(str(catalog.DESIGN_RULES.context_resource("topic_" + topic_id).title))
	var topic_help := "LOC_EVENT_RESPONSE_TARGET_TOPIC_HELP" if not str(record.get("target_variant_id", "")).is_empty() else "LOC_EVENT_RESPONSE_TOPIC_HELP"
	_append_clause(segments, [_field(DeskLocalization.source_join("LOC_EVENT_IMPACT_LIST_SEPARATOR", topics), topic_help, "topic", "")])
	var changes: Array[Dictionary] = []
	for metric: String in ["attention", "spread", "production"]:
		var amount := float(response[metric])
		if is_zero_approx(amount): continue
		if not changes.is_empty(): changes.append(_text("LOC_EVENT_IMPACT_LIST_SEPARATOR"))
		changes.append(_field("LOC_EVENT_RESPONSE_" + metric.to_upper(), "LOC_EVENT_RESPONSE_" + metric.to_upper() + "_HELP", "metric", ""))
		changes.append(_text(" " + _signed(amount * 100.0) + "%"))
	if not changes.is_empty():
		changes.append(_text(DeskLocalization.source_format("LOC_EVENT_IMPACT_DURATION", _number(float(record.response_duration_hours)))))
		_append_clause(segments, changes)
	var sentiment := float(response.sentiment)
	if not is_zero_approx(sentiment):
		var preference := "LOC_EVENT_RESPONSE_POSITIVE" if sentiment > 0.0 else "LOC_EVENT_RESPONSE_NEGATIVE"
		_append_clause(segments, [_field(preference, "LOC_EVENT_RESPONSE_SENTIMENT_HELP", "pragmatic_token", "")])
	var dissent: Dictionary = {}
	for cohort: Dictionary in response.cohorts:
		if is_zero_approx(float(cohort.share)): continue
		if float(cohort.sentiment) * sentiment >= 0.0: continue
		if dissent.is_empty() or float(cohort.sentiment) * sentiment < float(dissent.sentiment) * sentiment: dissent = cohort
	if not dissent.is_empty():
		var preference := "LOC_EVENT_RESPONSE_COHORT_POSITIVE" if float(dissent.sentiment) > 0.0 else "LOC_EVENT_RESPONSE_COHORT_NEGATIVE"
		var clause: Array[Dictionary] = [_field(str(COHORTS[str(dissent.id)]), "LOC_EVENT_RESPONSE_COHORT_HELP", "group", ""),
			_text(DeskLocalization.source_format("LOC_EVENT_RESPONSE_POPULATION_SHARE", _number(float(dissent.share) * 100.0))), _text(preference)]
		if float(dissent.irony) >= 0.15:
			clause.append(_text("LOC_EVENT_IMPACT_LIST_SEPARATOR"))
			clause.append(_field("LOC_EVENT_RESPONSE_IRONY", "LOC_EVENT_RESPONSE_IRONY_HELP", "pragmatic_token", ""))
			clause.append(_text(" " + _number(float(dissent.irony) * 100.0) + "%"))
		_append_clause(segments, clause)
	elif float(response.irony) >= 0.15:
		_append_clause(segments, [_field("LOC_EVENT_RESPONSE_IRONY", "LOC_EVENT_RESPONSE_IRONY_HELP", "pragmatic_token", ""), _text(" " + _number(float(response.irony) * 100.0) + "%")])

static func _groups(ids: PackedStringArray, catalog: MemeDemoCatalog) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	if ids.is_empty():
		segments.append(_field("LOC_EVENT_RESPONSE_LOCAL_AUDIENCE", "LOC_EVENT_RESPONSE_LOCAL_AUDIENCE_HELP", "group", ""))
	else:
		for id: String in ids:
			if not segments.is_empty(): segments.append(_text("LOC_EVENT_IMPACT_LIST_SEPARATOR"))
			var group: Dictionary = catalog.DESIGN_RULES.context_resource("group_" + id)
			segments.append(_field(str(group.title), CardCopy.hover_description("group_" + id), "group", CardCopy.hover_note("group_" + id)))
	return segments

static func _append_clause(segments: Array[Dictionary], clause: Array[Dictionary]) -> void:
	if not segments.is_empty(): segments.append(_text("\n"))
	segments.append_array(clause)

static func _field(title: String, body: String, kind: String, note: String) -> Dictionary:
	return {"text":title, "tooltip_title":title, "tooltip_body":body, "tooltip_note":note, "field_kind":kind}

static func _text(value: String) -> Dictionary:
	return {"text":value}

static func _number(value: float) -> String:
	return ("%.3f" % value).trim_suffix("000").trim_suffix("00").trim_suffix("0").trim_suffix(".")

static func _signed(value: float) -> String:
	return ("+" if value >= 0.0 else "") + _number(value)
