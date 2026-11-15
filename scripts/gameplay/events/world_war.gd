extends RefCounted

static func schedule(seed_value: int, country_ids: Array, min_hours: int, max_hours: int) -> Dictionary:
	var ids: Array[String] = []
	for id: String in country_ids: ids.append(id)
	ids.sort()
	var result := {}
	for id: String in ids:
		var random := RandomNumberGenerator.new()
		random.seed = ("world-war:%d:%s" % [seed_value, id]).hash()
		result[id] = random.randi_range(min_hours, max_hours)
	if not ids.is_empty():
		var random := RandomNumberGenerator.new()
		random.seed = ("world-war:last:%d" % seed_value).hash()
		result[ids[random.randi_range(0, ids.size() - 1)]] = max_hours
	return result

static func population(initial: int, elapsed: int, duration: int) -> int:
	if elapsed >= duration: return 0
	var remaining := 1.0 - float(elapsed) / float(duration)
	return floori(float(initial) * remaining * remaining * remaining)

static func carrier_countries(variants: Array, countries: Dictionary, current_id: String) -> Array[String]:
	var identity := ""
	for variant: Dictionary in variants:
		if str(variant.id) == current_id:
			identity = str(variant.get("meme_id", variant.id))
			break
	var active_ids: Array[String] = []
	for variant: Dictionary in variants:
		if not bool(variant.get("retired", false)) and not identity.is_empty() and str(variant.get("meme_id", variant.id)) == identity:
			active_ids.append(str(variant.id))
	var result: Array[String] = []
	for id: String in countries:
		var country: Dictionary = countries[id]
		for variant_id: String in active_ids:
			if int(country.adopted.get(variant_id, 0)) > 0 or int(country.exposed.get(variant_id, 0)) > 0:
				result.append(id)
				break
	result.sort()
	return result
