extends RefCounted
## 根据已验证的事件定义和运行计数选取事件，不创建事件身份或发放奖励。

static func arrival_count(clock: MemeDemoEventClock, seed_value: int, hour: int, arrivals_by_day: Dictionary) -> int:
	var arrivals := 0
	for day in floori(float(hour - 1) / 24.0) + 1:
		if not arrivals_by_day.has(day):
			arrivals_by_day[day] = clock.arrival_hours(seed_value, day)
		for arrival_hour: int in arrivals_by_day[day]:
			if arrival_hour <= hour: arrivals += 1
	return arrivals

static func choose_event(definitions: Array[MemeDemoEvent], hour: int, time_scale: float, event_counts: Dictionary, last_event_hours: Dictionary, condition_values: Dictionary, random: RandomNumberGenerator) -> MemeDemoEvent:
	var candidates: Array[MemeDemoEvent] = []
	var total_weight := 0.0
	for definition: MemeDemoEvent in definitions:
		var event_id := str(definition.id)
		var previous_count := int(event_counts.get(event_id, 0))
		if definition.weight <= 0.0 or hour < definition.start_hour * time_scale:
			continue
		if definition.max_occurrences > 0 and previous_count >= definition.max_occurrences:
			continue
		if last_event_hours.has(event_id) and hour - float(last_event_hours[event_id]) < definition.cooldown_hours * time_scale:
			continue
		if definition.trigger_mode == &"periodic" and previous_count > 0 and hour - float(last_event_hours[event_id]) < maxf(1.0, definition.decay_parameter_hours * time_scale):
			continue
		var qualified := true
		for condition: MemeDemoCondition in definition.conditions:
			qualified = qualified and _condition_passes(condition, condition_values)
		if not qualified or random.randf() >= definition.occurrence_chance:
			continue
		candidates.append(definition)
		total_weight += definition.weight
	if total_weight <= 0.0: return null
	var remaining_weight := random.randf() * total_weight
	for definition: MemeDemoEvent in candidates:
		remaining_weight -= definition.weight
		if remaining_weight < 0.0: return definition
	push_error("事件权重抽样未命中已验证的候选池。")
	return null

static func _condition_passes(condition: MemeDemoCondition, values: Dictionary) -> bool:
	var actual := float(values[str(condition.field)])
	match str(condition.operator):
		"ge": return actual >= condition.value
		"gt": return actual > condition.value
		"le": return actual <= condition.value
		"lt": return actual < condition.value
		"eq": return is_equal_approx(actual, condition.value)
	return false
