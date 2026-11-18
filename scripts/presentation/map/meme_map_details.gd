extends RefCounted

const CountryHover = preload("res://scripts/presentation/map/country_hover_content.gd")
const Identity = preload("res://scripts/presentation/memes/meme_identity.gd")
const CardCopy = preload("res://scripts/presentation/studio/paper/desk_material_card_copy.gd")
const MonitorMetrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const ENDING_ORDER := ["viral_icon", "local_classic", "successful_adaptation", "balanced_duel", "best_substitute", "forgotten"]

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
	var goals := _ending_rows(world, raw, country_titles, catalog.gameplay_rules)
	if not goals.is_empty(): sections.append(_section("MM_ENDING_PROGRESS", "ending", "MM_ENDING_PROGRESS_HELP", goals))
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
	var text := Identity.display_text(str(definition.title))
	var info := definition.duplicate(true) if definition.has("id") else {}
	var help := ""
	if not info.is_empty():
		CardCopy.apply_to(info)
		help = DeskLocalization.text(str(info.hover_description))
	if not attached: text += DeskLocalization.text("LOC_DETACHED_INACTIVE_F53886E7")
	return {"text":text, "kind":kind, "help_key":"", "help":help, "hover_info":info, "attached":attached}

static func monitor_metrics(snapshot: Dictionary, variant_id: String) -> Dictionary:
	var world: Dictionary = snapshot.world_competition
	var variant: Dictionary = world.variants_by_id[variant_id]
	var population := int(world.get("world_population", 0))
	if population == 0:
		for country: Dictionary in world.countries: population += int(country.population)
	var spread := float(variant.get("monitor_spread", MonitorMetrics.spread(variant, population, int(world.get("attention", {}).get("budget", 0)))))
	var raw := _raw_variant(snapshot, variant_id)
	var initial := MonitorMetrics.initial_variant(snapshot.lineage, raw)
	return {"spread":spread, "growth":float(variant.get("monitor_growth", 0.0)), "deviation":MonitorMetrics.deviation(initial, raw)}

static func _transmission_rows(snapshot: Dictionary, variant_id: String) -> Array[Dictionary]:
	var metrics := monitor_metrics(snapshot, variant_id)
	var growth := float(metrics.growth) * 100.0
	return [
		_row("MM_SPREAD", _share(float(metrics.spread)), "MM_HELP_SPREAD"),
		_row("MM_DEVIATION", _percentage(float(metrics.deviation)), "MM_HELP_DEVIATION"),
		_row("MM_GROWTH", ("+" if growth > 0.0 else "") + "%.1f%%" % growth, "MM_HELP_GROWTH")]

static func _ending_rows(world: Dictionary, raw: Dictionary, country_titles: Dictionary, rules: MemeGameplayRules) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if bool(world.endgame.war_started): return rows
	if not bool(raw.get("controlled", false)) or str(raw.get("creator", "")) != "player": return rows
	var meme_id := str(raw.get("meme_id", raw.id))
	for progress: Dictionary in world.ending_progress:
		if str(progress.meme_id) != meme_id: continue
		var id := str(progress.id)
		var values := PackedStringArray()
		var help := ""
		match id:
			"viral_icon", "best_substitute":
				if id == "best_substitute":
					values.append(DeskLocalization.text("MM_ENDING_PROGRESS_SPLIT"))
				values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_SPREAD", [_share(float(progress.spread)), _share(float(progress.spread_min))]))
				values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_LEAD", [_points(float(progress.lead)), _points(float(progress.lead_min))]))
			"local_classic":
				values.append(str(country_titles[str(progress.country_id)]) + " " + DeskLocalization.format_text("MM_ENDING_PROGRESS_ADOPTION", [_percentage(float(progress.adoption)), _percentage(float(progress.adoption_min))]))
				values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_DEVIATION", [_percentage(float(progress.deviation)), _percentage(float(progress.deviation_max))]))
				values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_RANGE", [_points(float(progress.range)), _points(float(progress.range_max))]))
			"balanced_duel":
				values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_BOTH", [_share(float(progress.spread)), _share(float(progress.other_spread)), _share(float(progress.spread_min))]))
				values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_GAP", [_points(float(progress.gap)), _points(float(progress.gap_max))]))
			"successful_adaptation":
				var baseline := float(progress.baseline) if bool(progress.adaptation_eligible) else float(progress.stable_peak)
				values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_BASELINE", [_percentage(baseline), _percentage(float(progress.baseline_min))]))
				if not bool(progress.adaptation_eligible): values.append(DeskLocalization.text("MM_ENDING_PROGRESS_REVISION"))
				values.append(str(country_titles[str(progress.country_id)]) + " " + DeskLocalization.format_text("MM_ENDING_PROGRESS_ADOPTION", [_percentage(float(progress.adoption)), _percentage(float(progress.adoption_min))]))
				var gain := _points(float(progress.gain)) if bool(progress.adaptation_eligible) else DeskLocalization.text("MM_ENDING_PROGRESS_UNREVISED")
				values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_GAIN", [gain, _points(float(progress.gain_min))]))
				help = DeskLocalization.format_text("MM_ENDING_PROGRESS_ADAPTATION_HELP", [rules.adaptation_stable_window_hours])
			"forgotten":
				if int(progress.get("forgotten_version", 1)) == 2:
					values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_LOW_REACH", [_percentage(float(progress.max_adoption)), _percentage(float(progress.max_adoption_max)), _share(float(progress.spread)), _share(float(progress.spread_max))]))
					values.append(DeskLocalization.text("MM_ENDING_PROGRESS_NOT_GROWING" if bool(progress.nonincreasing) else "MM_ENDING_PROGRESS_STILL_GROWING"))
					help = DeskLocalization.format_text("MM_ENDING_PROGRESS_FORGOTTEN_HELP", [int(progress.seed_required_hours), int(progress.required_hours)])
				else:
					values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_CARRIERS", [str(int(progress.adopted)), str(int(progress.exposed))]))
				values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_SEED", [int(progress.seed_hours), int(progress.seed_required_hours)]))
		values.append(DeskLocalization.format_text("MM_ENDING_PROGRESS_HOURS", [int(progress.hours), int(progress.required_hours)]))
		rows.append({"goal_id":id, "label":DeskLocalization.text("MM_ENDING_" + id.to_upper() + "_TITLE"), "value":" · ".join(values), "help_key":"", "help":help})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ENDING_ORDER.find(str(a.goal_id)) < ENDING_ORDER.find(str(b.goal_id)))
	return rows

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
