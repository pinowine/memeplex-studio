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

static func choose_event(definitions: Array[MemeDemoEvent], hour: int, time_scale: float, event_counts: Dictionary, last_event_hours: Dictionary, condition_values: Dictionary, random: RandomNumberGenerator, country: Dictionary = {}, reached: bool = true) -> MemeDemoEvent:
	var candidates: Array[MemeDemoEvent] = []
	var weights: Array[float] = []
	var total_weight := 0.0
	for definition: MemeDemoEvent in definitions:
		if not reached and definition.origin != &"world": continue
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
		var weight := definition.weight
		if not country.is_empty() and not definition.topic_ids.is_empty():
			var affinity := 0.0
			for topic: String in definition.topic_ids: affinity = maxf(affinity, float(country.topics.get(topic, 0.0)))
			weight *= affinity
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0.0: return null
	var remaining_weight := random.randf() * total_weight
	for index in candidates.size():
		remaining_weight -= weights[index]
		if remaining_weight < 0.0: return candidates[index]
	push_error(DeskLocalization.source("LOC_WEIGHTED_EVENT_SAMPLING_DID_NOT_SELECT_AN_01245473"))
	return null

static func country_weights(contributions: Dictionary) -> Dictionary:
	var total := 0.0
	var unreached := 0
	for value: float in contributions.values():
		total += value
		if value == 0.0: unreached += 1
	var result := {}
	for id: String in contributions:
		var contribution := float(contributions[id])
		if total == 0.0: result[id] = 1.0 / contributions.size()
		elif contribution == 0.0: result[id] = 0.1 / unreached
		else: result[id] = contribution / total * (0.9 if unreached > 0 else 1.0)
	return result

static func _condition_passes(condition: MemeDemoCondition, values: Dictionary) -> bool:
	var actual := float(values[str(condition.field)])
	match str(condition.operator):
		"ge": return actual >= condition.value
		"gt": return actual > condition.value
		"le": return actual <= condition.value
		"lt": return actual < condition.value
		"eq": return is_equal_approx(actual, condition.value)
	return false
