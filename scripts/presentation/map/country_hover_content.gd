extends RefCounted

const RULES = preload("res://data/rules/gameplay_rules.tres")
const CONTEXTS = preload("res://data/context/context_resources.tres")

static func _temperament_line(profile: Dictionary) -> String:
	var stance: Array = profile.get("stance", [0.0, 0.0])
	var pragmatic: Array = profile.get("pragmatic", [0.0, 0.0])
	var rule_key := "MAP_MOOD_FREEDOM" if float(stance[0]) <= -0.22 else ("MAP_MOOD_ORDER" if float(stance[0]) >= 0.22 else "MAP_MOOD_BALANCED_RULE")
	var rank_key := "MAP_MOOD_EQUAL" if float(stance[1]) <= -0.22 else ("MAP_MOOD_RANK" if float(stance[1]) >= 0.22 else "MAP_MOOD_BALANCED_RANK")
	var wit_key := "MAP_SPEECH_DIRECT" if float(pragmatic[0]) <= -0.20 else ("MAP_SPEECH_IRONIC" if float(pragmatic[0]) >= 0.20 else "MAP_SPEECH_BALANCED_WIT")
	var tone_key := "MAP_SPEECH_SUPPORT" if float(pragmatic[1]) <= -0.20 else ("MAP_SPEECH_SHARP" if float(pragmatic[1]) >= 0.20 else "MAP_SPEECH_BALANCED_TONE")
	return DeskLocalization.text("MAP_COUNTRY_MOOD_FORMAT") % [
		DeskLocalization.text(rule_key), DeskLocalization.text(rank_key),
		DeskLocalization.text(wit_key), DeskLocalization.text(tone_key)
	]

static func build(id: String, population: int = -1) -> Dictionary:
	var profile := RULES.country(id)
	var country: MapCountryDefinition
	for definition: MapCountryDefinition in RULES.map_settings.countries:
		if str(definition.id) == id: country = definition
	var rows: Array[Dictionary] = []
	for category: Array in [["language", "languages", "MM_LANGUAGE"], ["group", "groups", "MM_GROUP"], ["topic", "topics", "MM_TOPICS"]]:
		var weights: Dictionary = profile[category[1]]
		var ids := weights.keys()
		ids.sort_custom(func(a: String, b: String): return float(weights[a]) > float(weights[b]))
		var tags: Array[Dictionary] = []
		for value: String in ids:
			for entry: Dictionary in CONTEXTS.entries:
				if str(entry.kind) != category[0] or str(entry.get("value", "")) != value: continue
				var title := DeskLocalization.text(str(entry.title))
				var primary: bool = category[0] == "language" and value in profile.primary_languages
				tags.append({"text":title, "name":title, "share":float(weights[value]), "primary":primary, "kind":str(category[0])})
				break
			if tags.size() == 3: break
		rows.append({"label":DeskLocalization.text(str(category[2])), "tags":tags})
	var description := DeskLocalization.text(str(country.description_key)) + "\n\n" + _temperament_line(profile)
	return {"id":id, "kind":"country", "title":DeskLocalization.text(str(country.official_name_key)),
		"description":description, "rows":rows, "hover_width":420.0,
		"presentation":{"kind":"language", "grouped_bars":true,
		"badge":DeskLocalization.text("MAP_POPULATION") % (float(population if population >= 0 else profile.population)/1000000.0),
		"note":DeskLocalization.text(str(country.description_key) + "_NOTE")}}
