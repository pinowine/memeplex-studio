extends RefCounted

const POLICY_VERSION := 2
const FIRST_KEY := "propagation:first_adoption"
const FIRST_AMOUNT := 20
const RETURN_AMOUNTS := [20,19,18,17,15,12,10,9,8,7,6,5,4,3,2,1]
const PROGRESS_FIELDS := ["propagation_reward_version","propagation_adopted","propagation_landed","propagation_population","propagation_level"]

static func amount_for_level(level: int) -> int:
	return int(RETURN_AMOUNTS[level-1]) if level <= RETURN_AMOUNTS.size() else 1

static func adoption_increment(population: int, level: int) -> int:
	var factor := 1.0 + 0.42 * float(level-1)
	return maxi(1,ceili(float(population)*0.008*factor*factor))

static func country_increment(_level: int) -> int:
	return 1

static func minimum_interval(level: int) -> int:
	var factor := 1.0 + 0.15 * float(level-1)
	return ceili(8.0*factor*factor)

static func signature() -> String:
	return JSON.stringify({"version":POLICY_VERSION,"first":FIRST_AMOUNT,"amounts":RETURN_AMOUNTS,"adoption_fraction":0.008,"adoption_growth":0.42,"country_step":1,"interval_hours":8,"interval_growth":0.15,"tail_amount":1},"",true,true).sha256_text()

static func _fields(adopted: int, population: int, landed: int, level: int) -> Dictionary:
	return {"propagation_reward_version":POLICY_VERSION,"propagation_adopted":adopted,"propagation_landed":landed,"propagation_population":population,"propagation_level":level}

static func _last_record(transactions: Array) -> Dictionary:
	for index in range(transactions.size()-1,-1,-1):
		var entry: Dictionary = transactions[index]
		if str(entry.get("key","")).begins_with("propagation:"): return entry
	return {}

static func due_rewards(hour: int, first_publish_hour: int, owned_adopted: int, world_population: int, landed_count: int, transactions: Array, rewarded_keys: Dictionary) -> Array[Dictionary]:
	if owned_adopted <= 0 or hour < first_publish_hour: return []
	if not rewarded_keys.has(FIRST_KEY):
		return [{"key":FIRST_KEY,"amount":FIRST_AMOUNT,"reason_key":"LOC_PROP_FIRST_ADOPTION","reason_inputs":[],"ledger_fields":_fields(owned_adopted,world_population,landed_count,0)}]
	var previous := _last_record(transactions)
	var level := int(previous.propagation_level)+1
	if hour-int(previous.hour) < minimum_interval(level): return []
	var adopted_mark := int(previous.propagation_adopted)
	var landed_mark := int(previous.propagation_landed)
	var growth := owned_adopted-adopted_mark >= adoption_increment(world_population,level)
	var expansion := landed_count-landed_mark >= country_increment(level)
	if not growth and not expansion: return []
	var kind := "growth" if growth else "country"
	var key := "propagation:%s:%d" % [kind,level]
	if rewarded_keys.has(key): return []
	return [{"key":key,"amount":amount_for_level(level),"reason_key":"LOC_PROP_GROWTH_RETURN" if growth else "LOC_PROP_COUNTRY_RETURN","reason_inputs":[level],"ledger_fields":_fields(maxi(adopted_mark,owned_adopted),world_population,maxi(landed_mark,landed_count),level)}]

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func validate_ledger(transactions: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var previous := {}
	var seen_first := false
	for entry_value: Variant in transactions:
		if not entry_value is Dictionary: continue
		var entry: Dictionary = entry_value
		var key := str(entry.get("key",""))
		if not key.begins_with("propagation:"): continue
		var kind := "first"
		var level := 0
		if key != FIRST_KEY:
			var parts := key.split(":")
			if parts.size() != 3 or parts[1] not in ["growth","country"] or not parts[2].is_valid_int():
				errors.append("propagation rewards: unknown reward key")
				continue
			kind = parts[1]
			level = int(parts[2])
			if level < 1 or str(level) != parts[2]:
				errors.append("propagation rewards: noncanonical reward level")
				continue
		var typed := true
		for field: String in PROGRESS_FIELDS:
			if not _integer(entry.get(field)):
				errors.append("propagation rewards: missing or invalid " + field)
				typed = false
		if not _integer(entry.get("hour")) or not _integer(entry.get("delta")):
			errors.append("propagation rewards: invalid reward hour or amount")
			typed = false
		if not typed: continue
		var adopted := int(entry.propagation_adopted)
		var landed := int(entry.propagation_landed)
		var population := int(entry.propagation_population)
		if int(entry.propagation_reward_version) != POLICY_VERSION or int(entry.propagation_level) != level:
			errors.append("propagation rewards: policy or level mismatch")
		if population <= 0 or adopted <= 0 or landed < 0 or int(entry.hour) < 0:
			errors.append("propagation rewards: invalid progress watermark")
		if kind == "first":
			if seen_first or not previous.is_empty() or int(entry.delta) != FIRST_AMOUNT:
				errors.append("propagation rewards: invalid first-adoption reward")
			seen_first = true
		else:
			if not seen_first or previous.is_empty():
				errors.append("propagation rewards: progress requires first adoption")
				continue
			if level != int(previous.propagation_level)+1 or int(entry.delta) != amount_for_level(level):
				errors.append("propagation rewards: reward sequence or amount mismatch")
			if population != int(previous.propagation_population) or adopted < int(previous.propagation_adopted) or landed < int(previous.propagation_landed):
				errors.append("propagation rewards: progress watermark decreased")
			if int(entry.hour)-int(previous.hour) < minimum_interval(level):
				errors.append("propagation rewards: reward interval not reached")
			if population > 0:
				if kind == "growth" and adopted-int(previous.propagation_adopted) < adoption_increment(population,level):
					errors.append("propagation rewards: adoption threshold not reached")
				if kind == "country" and landed-int(previous.propagation_landed) < country_increment(level):
					errors.append("propagation rewards: expansion threshold not reached")
		previous = entry
	return errors
