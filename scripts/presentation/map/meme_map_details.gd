extends RefCounted

const Identity = preload("res://scripts/presentation/memes/meme_identity.gd")

static func short_name(snapshot: Dictionary, catalog: MemeDemoCatalog, variant_id: String) -> String:
	return Identity.name(catalog, _raw_variant(snapshot, variant_id))

static func build(snapshot: Dictionary, catalog: MemeDemoCatalog, variant_id: String) -> Dictionary:
	var world: Dictionary = snapshot.world_competition
	var variant: Dictionary = world.variants_by_id[variant_id]
	var raw := _raw_variant(snapshot, variant_id)
	var identity := Identity.resolve(catalog, raw)
	var profile: Dictionary = raw.flow_profile
	var country_titles := {}
	for country: Resource in catalog.gameplay_rules.map_settings.countries:
		country_titles[str(country.id)] = DeskLocalization.text(str(country.short_name_key))
	var channel_titles := {}
	for channel: Resource in catalog.channels:
		channel_titles[str(channel.id)] = Identity.display_text(str(channel.title))
	var content_rows: Array[Dictionary] = [_row("MM_EXPRESSION_TEXT", str(identity.expression), "MM_HELP_EXPRESSION_TEXT")]
	if not str(identity.meaning).is_empty():
		content_rows.append(_row("MM_MEANING", str(identity.meaning), "MM_HELP_MEANING"))
	var sections: Array[Dictionary] = [
		_section("MM_CONTENT", "meme", "MM_HELP_CONTENT", content_rows),
		_section("MM_COUNTRIES", "group", "MM_HELP_COUNTRIES", _country_rows(world, variant_id, country_titles)),
		_section("MM_CONTEXT", "language", "MM_HELP_CONTEXT", _context_rows(profile, catalog)),
		_section("MM_TRANSMISSION", "metric", "MM_HELP_TRANSMISSION", _transmission_rows(variant, profile, channel_titles))]
	var origin := str(variant.origin_country)
	return {"id":variant_id, "title":str(identity.name), "name":str(identity.name),
		"expression":str(identity.expression), "meaning":str(identity.meaning),
		"version":str(identity.version), "source_kind":str(identity.kind),
		"origin_country":origin, "origin_title":str(country_titles[origin]),
		"adopted":int(variant.adopted), "exposed":int(variant.exposed), "attention":int(variant.attention), "share":float(variant.share),
		"name_help_key":"MM_HELP_NAME", "name_help":DeskLocalization.text("MM_HELP_NAME"),
		"expression_help":DeskLocalization.text("MM_HELP_EXPRESSION_TEXT"), "meaning_help":DeskLocalization.text("MM_HELP_MEANING"),
		"origin_help":DeskLocalization.text("MM_HELP_ORIGIN"), "sections":sections}

static func build_hover(snapshot: Dictionary, catalog: MemeDemoCatalog, variant_id: String) -> Dictionary:
	var variant: Dictionary = snapshot.world_competition.variants_by_id[variant_id]
	var raw := _raw_variant(snapshot, variant_id)
	var groups := _context_groups(raw.flow_profile, catalog)
	var tags: Array[Dictionary] = []
	for kind: String in ["language", "group", "topic", "stance", "pragmatic"]:
		tags.append_array(groups[kind])
	return {"id":variant_id, "title":Identity.name(catalog, raw),
		"name_help_key":"MM_HELP_NAME", "name_help":DeskLocalization.text("MM_HELP_NAME"),
		"share":float(variant.share), "share_label":DeskLocalization.text("MM_SPREAD"),
		"share_value":_share(float(variant.share)), "share_help_key":"MM_HELP_SPREAD",
		"share_help":DeskLocalization.text("MM_HELP_SPREAD"), "context_tags":tags, "sections":[]}

static func _raw_variant(snapshot: Dictionary, variant_id: String) -> Dictionary:
	for raw: Dictionary in snapshot.lineage:
		if str(raw.id) == variant_id: return raw
	return {}

static func _country_rows(world: Dictionary, variant_id: String, titles: Dictionary) -> Array[Dictionary]:
	var positions: Array[Dictionary] = []
	for country: Dictionary in world.countries:
		for presence: Dictionary in country.variants:
			if str(presence.id) != variant_id: continue
			if int(presence.adopted) > 0 or int(presence.exposed) > 0:
				positions.append({"country_id":str(country.id), "adopted":int(presence.adopted),
					"exposed":int(presence.exposed), "attention":int(presence.attention),
					"share":float(presence.adopted) / int(country.population)})
			break
	positions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.adopted) != int(b.adopted): return int(a.adopted) > int(b.adopted)
		if int(a.exposed) != int(b.exposed): return int(a.exposed) > int(b.exposed)
		return str(a.country_id) < str(b.country_id))
	var rows: Array[Dictionary] = []
	for position: Dictionary in positions:
		var row := _row("", _share(float(position.share)), "MM_HELP_COUNTRY_SPREAD")
		row.merge(position)
		row.label = str(titles[str(position.country_id)])
		rows.append(row)
		rows.append(_row("MM_ADOPTION", _number(int(position.adopted)), "MM_HELP_LOCAL_ADOPTION"))
		rows.append(_row("MM_EXPOSURE", _number(int(position.exposed)), "MM_HELP_LOCAL_EXPOSURE"))
		rows.append(_row("MM_ATTENTION", _number(int(position.attention)), "MM_HELP_LOCAL_ATTENTION"))
	return rows

static func _context_rows(profile: Dictionary, catalog: MemeDemoCatalog) -> Array[Dictionary]:
	var groups := _context_groups(profile, catalog)
	var rows: Array[Dictionary] = []
	for field: Array in [["MM_LANGUAGE", "language", "MM_HELP_LANGUAGE"], ["MM_GROUP", "group", "MM_HELP_GROUP"],
		["MM_TOPICS", "topic", "MM_HELP_TOPICS"], ["MM_STANCE", "stance", "MM_HELP_STANCE"], ["MM_PRAGMATICS", "pragmatic", "MM_HELP_PRAGMATICS"]]:
		var tags: Array = groups[str(field[1])]
		var values := PackedStringArray()
		for tag: Dictionary in tags: values.append(str(tag.text))
		var row := _row(str(field[0]), "\n".join(values), str(field[2]))
		row.tags = tags
		rows.append(row)
	return rows

static func _context_groups(profile: Dictionary, catalog: MemeDemoCatalog) -> Dictionary:
	var definitions := {}
	for entry: Dictionary in catalog.DESIGN_RULES.context_definitions.entries:
		definitions[str(entry.kind) + "/" + str(entry.value)] = entry
	var groups := {"language":[], "group":[], "topic":[], "stance":[], "pragmatic":[]}
	for kind: String in ["language", "group", "topic"]:
		var layer := "topics" if kind == "topic" else kind
		var ids: Array = profile.topic_ids if kind == "topic" else profile.get(kind + "_ids", [str(profile[kind + "_id"])])
		for id: String in ids:
			groups[kind].append(_tag(kind, definitions[kind + "/" + id], bool(profile.context_layer_attachment[layer])))
	for layer: String in ["stance", "pragmatic"]:
		var point: Array = profile.political_position if layer == "stance" else profile.pragmatic_position
		var axes := [["freedom", "authority"], ["equality", "hierarchy"]] if layer == "stance" else [["sincere", "ironic"], ["support", "opposition"]]
		if layer != "stance" or bool(profile.political_known):
			for index in 2:
				if is_zero_approx(float(point[index])): continue
				var id: String = axes[index][1 if float(point[index]) > 0.0 else 0]
				groups[layer].append(_tag(layer, definitions[layer + "_token/" + id], bool(profile.context_layer_attachment[layer])))
		if groups[layer].is_empty():
			var key := "LOC_STARTER_STANCE_UNSET" if layer == "stance" and not bool(profile.political_known) else ("LOC_STARTER_POLITICAL_NEUTRAL" if layer == "stance" else "LOC_STARTER_AXIS_CENTER")
			groups[layer].append(_tag(layer, {"title":key, "description":""}, bool(profile.context_layer_attachment[layer])))
	return groups

static func _tag(kind: String, definition: Dictionary, attached: bool) -> Dictionary:
	var help_key: String = {"language":"MM_HELP_LANGUAGE", "group":"MM_HELP_GROUP", "topic":"MM_HELP_TOPICS", "stance":"MM_HELP_STANCE", "pragmatic":"MM_HELP_PRAGMATICS"}[kind]
	var text := Identity.display_text(str(definition.title))
	var help := DeskLocalization.text(help_key)
	if not str(definition.get("description", "")).is_empty():
		help = Identity.display_text(str(definition.description)) + "\n" + help
	if not attached:
		text += DeskLocalization.text("LOC_DETACHED_INACTIVE_F53886E7")
		help += "\n" + DeskLocalization.text("MM_HELP_DETACHED")
	return {"text":text, "kind":kind, "help_key":help_key, "help":help, "attached":attached}

static func _transmission_rows(variant: Dictionary, profile: Dictionary, channel_titles: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [
		_row("MM_GLOBAL_ADOPTION", _number(int(variant.adopted)), "MM_HELP_ADOPTION"),
		_row("MM_GLOBAL_EXPOSURE", _number(int(variant.exposed)), "MM_HELP_EXPOSURE"),
		_row("MM_GLOBAL_ATTENTION", _number(int(variant.attention)), "MM_HELP_ATTENTION"),
		_row("MM_SPREAD", _share(float(variant.share)), "MM_HELP_SPREAD"),
		_row("MM_CHANNEL", str(channel_titles[str(profile.channel_id)]), "MM_HELP_CHANNEL"),
		_row("MM_REACH", "×%.2f" % float(profile.reach), "MM_HELP_REACH")]
	for pair: Array in [["MM_LANGUAGE_ACCESS", "language_access"], ["MM_RECOGNIZABILITY", "recognizability"],
		["MM_CONTEXT_DEPENDENCY", "context_dependency"], ["MM_REMIX_COST", "remix_cost"], ["MM_EXPRESSION", "expression"]]:
		rows.append(_row(str(pair[0]), _percentage(float(profile[str(pair[1])])), "MM_HELP_" + str(pair[1]).to_upper()))
	return rows

static func _section(title_key: String, kind: String, help_key: String, rows: Array[Dictionary]) -> Dictionary:
	return {"title":DeskLocalization.text(title_key), "kind":kind, "help_key":help_key, "help":DeskLocalization.text(help_key), "rows":rows}

static func _row(label_key: String, value: String, help_key: String) -> Dictionary:
	return {"label":DeskLocalization.text(label_key) if not label_key.is_empty() else "", "value":value,
		"help_key":help_key, "help":DeskLocalization.text(help_key)}

static func _percentage(value: float) -> String:
	return "%.1f%%" % (value * 100.0)

static func _share(value: float) -> String:
	var percent := value * 100.0
	return "<0.01%" if percent > 0.0 and percent < 0.01 else "%.2f%%" % percent

static func _number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0: result += ","
		result += digits[index]
	return result
