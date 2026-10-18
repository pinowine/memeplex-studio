class_name MemeContextDefinitions
extends Resource

@export var entries: Array[Dictionary] = []

func validate(catalog: Resource) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var tokens := {"freedom":["stance_token","x",-1],"authority":["stance_token","x",1],"equality":["stance_token","y",-1],"hierarchy":["stance_token","y",1],"sincere":["pragmatic_token","x",-1],"ironic":["pragmatic_token","x",1],"support":["pragmatic_token","y",-1],"opposition":["pragmatic_token","y",1]}
	for entry in entries:
		var id := str(entry.get("id", ""))
		var kind := str(entry.get("kind", ""))
		if id.is_empty() or seen.has(id) or kind not in ["language", "group", "topic", "stance_token", "pragmatic_token"] or str(entry.get("title", "")).is_empty() or not entry.get("initial_count") is int or int(entry.initial_count) < 0 or int(entry.initial_count) > 1000:
			errors.append("Invalid context resource")
		seen[id] = true
		var value := str(entry.get("value", ""))
		if kind in ["stance_token","pragmatic_token"]:
			if not tokens.has(id) or tokens[id] != [kind,str(entry.get("axis","")),entry.get("direction")]: errors.append("Invalid endpoint token mapping")
		if kind == "language" and value not in ["zh", "en", "mixed"]: errors.append("Unknown language context")
		if kind == "topic" and value not in catalog.topics: errors.append("Unknown topic context")
		if kind == "group":
			var found := false
			for group in catalog.groups: found = found or str(group.id) == value
			if not found: errors.append("Unknown group context")
	for id in tokens:
		if not seen.has(id): errors.append("Missing endpoint token: "+id)
	return errors
