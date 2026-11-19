@tool
class_name MemeContextDefinitions
extends Resource

@export var entries: Array[Dictionary] = []:
	set(value):
		entries = DeskLocalization.source_value(value)

func values(kind: String) -> PackedStringArray:
	var result := PackedStringArray()
	for entry: Dictionary in entries:
		if str(entry.get("kind", "")) == kind: result.append(str(entry.get("value", "")))
	return result

func validate(catalog: Resource) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var values_by_kind := {"language":{}, "group":{}, "topic":{}}
	var tokens := {"freedom":["stance_token","x",-1],"authority":["stance_token","x",1],"equality":["stance_token","y",-1],"hierarchy":["stance_token","y",1],"sincere":["pragmatic_token","x",-1],"ironic":["pragmatic_token","x",1],"support":["pragmatic_token","y",-1],"opposition":["pragmatic_token","y",1]}
	for entry in entries:
		var id := str(entry.get("id", ""))
		var kind := str(entry.get("kind", ""))
		if id.is_empty() or seen.has(id) or kind not in ["language", "group", "topic", "stance_token", "pragmatic_token"] or str(entry.get("title", "")).is_empty() or not entry.get("initial_count") is int or int(entry.initial_count) < 0 or int(entry.initial_count) > 1000:
			errors.append("Invalid context resource")
		seen[id] = true
		if kind in ["language","group","topic"] and int(entry.get("initial_count",0)) > 1: errors.append("Context cards must be unique")
		var value := str(entry.get("value", ""))
		if kind in values_by_kind:
			if value.is_empty() or values_by_kind[kind].has(value) or id != kind + "_" + value:
				errors.append("Invalid or repeated context value: " + id)
			values_by_kind[kind][value] = true
		if kind in ["stance_token","pragmatic_token"]:
			if not tokens.has(id) or tokens[id] != [kind,str(entry.get("axis","")),entry.get("direction")]: errors.append("Invalid endpoint token mapping")
		if kind == "topic" and value not in catalog.topics: errors.append("Unknown topic context")
		if kind == "group":
			var found := false
			for group in catalog.groups: found = found or str(group.id) == value
			if not found: errors.append("Unknown group context")
	for id in tokens:
		if not seen.has(id): errors.append("Missing endpoint token: "+id)
	for group: Resource in catalog.groups:
		if not values_by_kind.group.has(str(group.id)): errors.append("Missing group context: " + str(group.id))
		if not values_by_kind.language.has(str(group.language_id)): errors.append("Unknown group language: " + str(group.language_id))
	for topic: String in catalog.topics:
		if not values_by_kind.topic.has(topic): errors.append("Missing topic context: " + topic)
	if catalog.gameplay_rules != null:
		for country: Dictionary in catalog.gameplay_rules.countries:
			for pair: Array in [["language", "languages"], ["group", "groups"], ["topic", "topics"]]:
				var expected: Dictionary = values_by_kind[pair[0]]
				var actual: Dictionary = country[pair[1]]
				for value: String in expected:
					if not actual.has(value): errors.append("Missing country " + str(pair[0]) + ": " + str(country.id) + "/" + value)
				for value: String in actual:
					if not expected.has(value): errors.append("Unknown country " + str(pair[0]) + ": " + str(country.id) + "/" + value)
	return errors
