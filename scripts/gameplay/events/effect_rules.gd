extends RefCounted
## 只计算吸引衰减和重混表达，不修改传播状态、来源账本或随机数。

static func attraction_factor(modifiers: Array[Dictionary], hour: int, group_id: String, topics: PackedStringArray) -> float:
	var factor := 1.0
	for modifier: Dictionary in modifiers:
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

static func reuse_factor(permission: String, replaceable_slot_count: int, required_slot_count: int, remix_cost: float, context_dependency: float) -> float:
	var permission_factor := 0.6 if permission == "conditional" else 1.0
	var replaceability := float(replaceable_slot_count) / maxf(1.0, required_slot_count)
	return permission_factor * (0.3 + 0.7 * replaceability) * (1.0 - remix_cost * 0.7) * (1.0 - context_dependency * 0.5)

static func remix_text(event_definition_id: String, parent_text: String) -> String:
	match event_definition_id:
		"cross_language": return "Not a privilege, just a daily trip. / 日常通勤不是特权。"
		"platform_tool": return "用我的日常账单重填这张模板：" + parent_text
		"semantic_split": return "涨价才是公平：谁用得多，谁就该付得多。"
		"critical_quote": return "反讽引用：你说这是公平，我看到的是谁被留在站外。"
	return "群体重写：" + parent_text
