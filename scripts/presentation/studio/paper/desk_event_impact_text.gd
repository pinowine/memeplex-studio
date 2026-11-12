extends RefCounted

const CardCopy = preload("res://scripts/presentation/studio/paper/desk_material_card_copy.gd")

const METRICS := {
	"attention":["LOC_EVENT_IMPACT_ATTRACTION", "LOC_EVENT_IMPACT_ATTRACTION_HELP", "LOC_EVENT_NOTE_ATTRACTION"],
	"channel_reach":["LOC_EVENT_IMPACT_REACH", "LOC_EVENT_IMPACT_REACH_HELP", "LOC_EVENT_NOTE_REACH"],
	"trust":["LOC_TRUST_D1CD931B", "LOC_EVENT_IMPACT_TRUST_HELP", "LOC_EVENT_NOTE_TRUST"],
	"fatigue":["LOC_FATIGUE_9211F063", "LOC_EVENT_IMPACT_FATIGUE_HELP", "LOC_EVENT_NOTE_FATIGUE"],
	"revival":["LOC_FATIGUE_9211F063", "LOC_EVENT_IMPACT_FATIGUE_HELP", "LOC_EVENT_NOTE_FATIGUE"],
	"adoption":["LOC_EVENT_IMPACT_ADOPTION", "LOC_EVENT_IMPACT_ADOPTION_HELP", "LOC_EVENT_NOTE_ADOPTION"],
	"remix":["LOC_EVENT_IMPACT_REMIX", "LOC_EVENT_IMPACT_REMIX_HELP", "LOC_EVENT_NOTE_REMIX"],
	"semantic_shift":["LOC_EVENT_IMPACT_DRIFT", "LOC_EVENT_IMPACT_DRIFT_HELP", "LOC_EVENT_NOTE_DRIFT"]
}

static func build(record: Dictionary, catalog: MemeDemoCatalog, variants: Array) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	if record.is_empty(): return segments
	var definition: MemeDemoEvent
	for candidate: MemeDemoEvent in catalog.events:
		if str(candidate.id) == str(record.definition_id): definition = candidate
	var created := {"remix":0, "independent":0}
	for variant: Dictionary in variants:
		if str(variant.id) in record.competition_variant_ids:
			created["independent" if variant.parent_ids.is_empty() else "remix"] += 1
	for effect: MemeDemoEffect in definition.effects:
		var kind := str(effect.effect_id)
		var clause: Array[Dictionary] = []
		if kind in ["attention", "channel_reach"]:
			clause.append(_text(DeskLocalization.source_format("LOC_EVENT_IMPACT_DURATION", _number(maxf(1.0, effect.duration_hours * catalog.gameplay_rules.event_time_scale)))))
		if kind in ["attention", "channel_reach", "trust", "fatigue", "revival"]:
			clause.append_array(_groups(effect.group_ids, catalog))
			clause.append(_text("LOC_EVENT_IMPACT_POSSESSIVE"))
		var metric: Array = METRICS[kind]
		var help := str(metric[1])
		if kind in ["attention", "channel_reach"]:
			var topics := PackedStringArray()
			for topic_id: String in definition.topic_ids:
				topics.append(str(catalog.DESIGN_RULES.context_resource("topic_" + topic_id).title))
			help = DeskLocalization.source_format("LOC_EVENT_IMPACT_TOPIC_HELP", [help, DeskLocalization.source_join("LOC_EVENT_IMPACT_LIST_SEPARATOR", topics)], [0, 1])
		clause.append(_field(str(metric[0]), help, "metric", str(metric[2])))
		match kind:
			"attention", "channel_reach":
				clause.append(_text(" " + _signed((maxf(0.05, 1.0 + effect.amount) - 1.0) * 100.0) + "%"))
			"trust", "fatigue", "revival":
				var amount := -maxf(0.0, effect.amount) if kind == "revival" else effect.amount
				clause.append(_text(" "))
				clause.append(_text(DeskLocalization.source_format("LOC_EVENT_IMPACT_POINTS", _signed(amount * 100.0))))
			"adoption":
				clause.append(_text(" " + _signed(effect.amount * 100.0) + "%"))
			"semantic_shift":
				clause.append(_text(" = " + _number(effect.amount * 100.0) + "%"))
			"remix":
				clause.append(_text(" +%d" % int(created.remix)))
		_append_clause(segments, clause)
	if int(created.independent) > 0:
		_append_clause(segments, [_field("LOC_EVENT_IMPACT_INDEPENDENT", "LOC_EVENT_IMPACT_INDEPENDENT_HELP", "meme", "LOC_EVENT_NOTE_INDEPENDENT"), _text(" +%d" % int(created.independent))])
	for reward: Dictionary in record.design_rewards:
		var entry: Dictionary = catalog.DESIGN_RULES.reward_resource(str(reward.kind), str(reward.id))
		var description := CardCopy.hover_description(str(reward.id))
		_append_clause(segments, [_field(str(entry.title), description, str(reward.kind), CardCopy.hover_note(str(reward.id))), _text(" +%d" % int(reward.count))])
	return segments

static func _groups(ids: PackedStringArray, catalog: MemeDemoCatalog) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	if ids.is_empty():
		segments.append(_field("LOC_EVENT_IMPACT_GROUP_ALL", "LOC_EVENT_IMPACT_GROUP_ALL_HELP", "group", "LOC_EVENT_NOTE_ALL_GROUPS"))
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
