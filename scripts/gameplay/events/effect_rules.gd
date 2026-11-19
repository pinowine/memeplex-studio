extends RefCounted
const EventResponse = preload("res://scripts/gameplay/events/event_response.gd")
## 只计算吸引衰减和重混表达，不修改传播状态、来源账本或随机数。

static func attraction_factor(modifiers: Array[Dictionary], hour: int, group_id: String, topics: PackedStringArray) -> float:
	var factor := 1.0
	for modifier: Dictionary in modifiers:
		if modifier.has("country_id"): continue
		if not modifier.groups.is_empty() and group_id not in modifier.groups:
			continue
		var topic_matches: bool = modifier.topics.is_empty()
		for topic: String in topics:
			topic_matches = topic_matches or topic in modifier.topics
		if not topic_matches: continue
		var elapsed_hours := hour - float(modifier.starts)
		var duration_hours := maxf(1.0, float(modifier.expires) - float(modifier.starts))
		var decay := 1.0
		match str(modifier.decay):
			"linear": decay = maxf(0.0, 1.0 - elapsed_hours / duration_hours)
			"exponential": decay = exp(-elapsed_hours / maxf(0.01, float(modifier.decay_parameter)))
			"periodic": decay = 0.5 + 0.5 * cos(TAU * elapsed_hours / maxf(1.0, float(modifier.decay_parameter)))
		factor *= maxf(0.05, 1.0 + float(modifier.amount) * decay)
	return factor

static func decay_weight(modifier: Dictionary, hour: int) -> float:
	var elapsed := float(hour) - float(modifier.starts)
	var duration := maxf(1.0, float(modifier.expires) - float(modifier.starts))
	match str(modifier.decay):
		"linear": return maxf(0.0, 1.0 - elapsed / duration)
		"exponential": return exp(-elapsed / float(modifier.decay_parameter))
		"periodic": return 0.5 + 0.5 * cos(TAU * elapsed / float(modifier.decay_parameter))
	return 1.0

static func country_factor(modifiers: Array[Dictionary], hour: int, country_id: String, variant_id: String, profile: Dictionary) -> float:
	var factor := 1.0
	for modifier: Dictionary in modifiers:
		if str(modifier.get("country_id", "")) != country_id: continue
		if not modifier.variant_ids.is_empty() and variant_id not in modifier.variant_ids: continue
		if not modifier.groups.is_empty() and str(profile.group_id) not in modifier.groups and not _intersects(modifier.groups, profile.get("group_ids", [])): continue
		if not modifier.topics.is_empty() and not _intersects(modifier.topics, profile.topic_ids): continue
		var strength := decay_weight(modifier, hour)
		if str(modifier.effect_id) == "response":
			var response: Dictionary = modifier.response
			var response_factor := maxf(0.05, 1.0 + float(response.attention) * strength)
			response_factor *= maxf(0.05, 1.0 + float(response.spread) * strength)
			response_factor *= lerpf(1.0, EventResponse.preference(response, profile), strength)
			if response_factor < 1.0 and "meme_entry" in profile.get("skill_ids", []):
				response_factor = lerpf(1.0, response_factor, 0.5)
			factor *= response_factor
		else:
			var mod_factor := maxf(0.05, 1.0 + float(modifier.amount) * strength)
			if mod_factor < 1.0 and "meme_entry" in profile.get("skill_ids", []):
				mod_factor = lerpf(1.0, mod_factor, 0.5)
			factor *= mod_factor
	return factor

static func _intersects(left: Array, right: Array) -> bool:
	for id: Variant in left:
		if id in right: return true
	return false

static func reuse_factor(permission: String, replaceable_slot_count: int, required_slot_count: int, remix_cost: float, context_dependency: float) -> float:
	var permission_factor := 0.6 if permission == "conditional" else 1.0
	var replaceability := float(replaceable_slot_count) / maxf(1.0, required_slot_count)
	return permission_factor * (0.3 + 0.7 * replaceability) * (1.0 - remix_cost * 0.7) * (1.0 - context_dependency * 0.5)
