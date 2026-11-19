extends RefCounted

const CountryHover = preload("res://scripts/presentation/map/country_hover_content.gd")
const Identity = preload("res://scripts/presentation/memes/meme_identity.gd")
const CardCopy = preload("res://scripts/presentation/studio/paper/desk_material_card_copy.gd")
const MonitorMetrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const Deviation = preload("res://scripts/gameplay/competition/meme_deviation.gd")

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
	var content_rows: Array[Dictionary] = [_row("MM_EXPRESSION_TEXT", str(identity.expression), "MM_HELP_EXPRESSION_TEXT")]
	if not str(identity.meaning).is_empty():
		content_rows.append(_row("MM_MEANING", str(identity.meaning), "MM_HELP_MEANING"))
	var sections: Array[Dictionary] = [
		_section("MM_CONTENT", "meme", "MM_HELP_CONTENT", content_rows),
		_section("MM_TRANSMISSION", "metric", "MM_HELP_TRANSMISSION", _transmission_rows(snapshot, variant_id))]
	sections.append(_section("MM_COUNTRIES", "group", "MM_HELP_COUNTRIES", _country_rows(world, variant_id, country_titles)))
	sections.append(_section("MM_CONTEXT", "language", "MM_HELP_CONTEXT", _context_rows(profile, catalog)))
	var origin := str(variant.origin_country)
	return {"id":variant_id, "title":str(identity.name), "name":str(identity.name),
		"expression":str(identity.expression), "meaning":str(identity.meaning),
		"meme_id":str(raw.meme_id), "source_kind":str(identity.kind),
		"kind_help":DeskLocalization.text("MM_KIND_OWN_HELP" if bool(raw.get("controlled", false)) and str(raw.get("creator", "")) == "player" else "MM_KIND_INDEPENDENT_HELP"),
		"origin_hover":CountryHover.build(origin), "history":snapshot.get("meme_trends", {}).get(str(raw.meme_id), []),
		"origin_country":origin, "origin_title":str(country_titles[origin]),
		"adopted":int(variant.adopted), "exposed":int(variant.exposed), "attention":int(variant.attention), "share":float(variant.share),
		"name_help_key":"MM_HELP_NAME", "name_help":DeskLocalization.text("MM_HELP_NAME"),
		"expression_help":DeskLocalization.text("MM_HELP_EXPRESSION_TEXT"), "meaning_help":DeskLocalization.text("MM_HELP_MEANING"),
		"origin_help":DeskLocalization.text("MM_HELP_ORIGIN"), "sections":sections}

static func build_hover(snapshot: Dictionary, catalog: MemeDemoCatalog, variant_id: String) -> Dictionary:
	var variant: Dictionary = snapshot.world_competition.variants_by_id[variant_id]
	var raw := _raw_variant(snapshot, variant_id)
	var metrics := monitor_metrics(snapshot, variant_id)
	var groups := _context_groups(raw.flow_profile, catalog)
	var tags: Array[Dictionary] = []
	for kind: String in ["language", "group", "topic", "stance", "pragmatic"]:
		tags.append_array(groups[kind])
	return {"id":variant_id, "title":Identity.name(catalog, raw),
		"meaning":str(Identity.resolve(catalog, raw).meaning), "deviation":float(metrics.deviation),
		"history":snapshot.get("meme_trends", {}).get(str(raw.meme_id), []),
		"name_help_key":"MM_HELP_NAME", "name_help":DeskLocalization.text("MM_HELP_NAME"),
		"share":float(metrics.spread), "share_label":DeskLocalization.text("MM_SPREAD"),
		"share_value":_share(float(metrics.spread)), "share_help_key":"MM_HELP_SPREAD",
		"share_help":DeskLocalization.text("MM_HELP_SPREAD"), "context_tags":tags, "sections":[]}

static func _raw_variant(snapshot: Dictionary, variant_id: String) -> Dictionary:
	for raw: Dictionary in snapshot.lineage:
		if str(raw.id) == variant_id: return raw
	return {}

static func _country_rows(world: Dictionary, variant_id: String, titles: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for country: Dictionary in world.countries:
		for presence: Dictionary in country.variants:
			if str(presence.id) != variant_id: continue
			if int(presence.adopted) > 0 or int(presence.exposed) > 0:
				var row := _row("", "", "MM_HELP_COUNTRY_SPREAD")
				row.country_id = str(country.id)
				row.label = str(titles[str(country.id)])
				row.hover_info = CountryHover.build(str(country.id), int(country.population))
				rows.append(row)
			break
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
		row.help = ""
		row.hover_info = tags[0].hover_info if tags.size() == 1 else {}
		rows.append(row)
	return rows

static func _context_groups(profile: Dictionary, catalog: MemeDemoCatalog) -> Dictionary:
	var definitions := {}
	for entry: Dictionary in catalog.DESIGN_RULES.context_definitions.entries:
		definitions[str(entry.kind) + "/" + str(entry.value)] = entry
	var groups := {"language":[], "group":[], "topic":[], "stance":[], "pragmatic":[]}
	for kind: String in ["language", "group", "topic"]:
		var ids: Array = profile.topic_ids if kind == "topic" else profile.get(kind + "_ids", [str(profile[kind + "_id"])])
		for id: String in ids:
			groups[kind].append(_tag(kind, definitions[kind + "/" + id]))
	for layer: String in ["stance", "pragmatic"]:
		var point: Array = profile.political_position if layer == "stance" else profile.pragmatic_position
		var axes := [["freedom", "authority"], ["equality", "hierarchy"]] if layer == "stance" else [["sincere", "ironic"], ["support", "opposition"]]
		if layer != "stance" or bool(profile.political_known):
			for index in 2:
				if is_zero_approx(float(point[index])): continue
				var id: String = axes[index][1 if float(point[index]) > 0.0 else 0]
				groups[layer].append(_tag(layer, definitions[layer + "_token/" + id]))
		if groups[layer].is_empty():
			var key := "LOC_STARTER_STANCE_UNSET" if layer == "stance" and not bool(profile.political_known) else ("LOC_STARTER_POLITICAL_NEUTRAL" if layer == "stance" else "LOC_STARTER_AXIS_CENTER")
			groups[layer].append(_tag(layer, {"title":key, "description":""}))
	return groups

static func _tag(kind: String, definition: Dictionary) -> Dictionary:
	var text := Identity.display_text(str(definition.title))
	var info := definition.duplicate(true) if definition.has("id") else {}
	var help := ""
	if not info.is_empty():
		CardCopy.apply_to(info)
		help = DeskLocalization.text(str(info.hover_description))
	return {"text":text, "kind":kind, "help_key":"", "help":help, "hover_info":info}

static func monitor_metrics(snapshot: Dictionary, variant_id: String) -> Dictionary:
	var world: Dictionary = snapshot.world_competition
	var variant: Dictionary = world.variants_by_id[variant_id]
	var population := int(world.get("world_population", 0))
	if population == 0:
		for country: Dictionary in world.countries: population += int(country.population)
	var spread := float(variant.get("monitor_spread", MonitorMetrics.spread(variant, population, int(world.get("attention", {}).get("budget", 0)))))
	var raw := _raw_variant(snapshot, variant_id)
	var initial := MonitorMetrics.initial_variant(snapshot.lineage, raw)
	return {"spread":spread, "growth":float(variant.get("monitor_growth", 0.0)), "deviation":Deviation.total(initial, raw), "deviation_threshold":load("res://scripts/gameplay/propagation/propagation_rules.gd").new().split_threshold(.5, raw, {"flow_draft":raw.get("flow_draft", {})})}

static func _transmission_rows(snapshot: Dictionary, variant_id: String) -> Array[Dictionary]:
	var metrics := monitor_metrics(snapshot, variant_id)
	var growth := float(metrics.growth) * 100.0
	return [
		_row("MM_SPREAD", _share(float(metrics.spread)), "MM_HELP_SPREAD"),
		_row("MM_DEVIATION", _percentage(float(metrics.deviation)), "MM_HELP_DEVIATION"),
		_row("MM_GROWTH", ("+" if growth > 0.0 else "") + "%.1f%%" % growth, "MM_HELP_GROWTH")]

static func _points(value: float) -> String:
	return "%.1f" % (value * 100.0)

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
