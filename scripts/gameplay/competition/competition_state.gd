extends RefCounted

const Generator = preload("res://scripts/gameplay/map/map_generator.gd")
const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")
const EffectRules = preload("res://scripts/gameplay/events/effect_rules.gd")
const MonitorMetrics = preload("res://scripts/gameplay/competition/meme_monitor_metrics.gd")
const IndependentEndings = preload("res://scripts/gameplay/competition/independent_endings.gd")
const PropagationRules = preload("res://scripts/gameplay/propagation/propagation_rules.gd")
const INHERITED_PROFILE_VERSION := 2
static var _geography_cache: Dictionary = {}
var rules: MemeGameplayRules
var catalog: MemeDemoCatalog
var _state: Dictionary = {}
var _fitness_cache: Dictionary = {}
var _monitor_previous_scores: Dictionary = {}
var propagation_rules := PropagationRules.new()

func _init(content: MemeDemoCatalog = null) -> void:
	catalog = content
	if content != null: rules = content.gameplay_rules

func reset(world: RefCounted = null) -> void:
	_monitor_previous_scores.clear()
	_fitness_cache.clear()
	_state = {"competition_version":1,"policy_signature":rules.signature(),"world_seed":rules.reference_geometry_seed,"world":[],"populations":{},"countries":{},"registry":{},"hour":0,"active_seconds":0.0,"hour_credit":0.0,"ending_evaluated_hour":0,"equilibrium_hours":0,"equilibrium_candidate_hour":-1,"equilibrium_ranges":{},"autonomous_hours":0,"previous_shares":{},"ending_progress":{},"victory":{},"propagation":_empty_propagation_state()}
	if world == null:
		_set_world(_reference_world(int(rules.reference_geometry_seed)))
	else:
		_state.world_seed = int(world.seed_value)
		var rows := _world_rows(world)
		_geography_cache[_state.policy_signature+":"+str(world.seed_value)] = rows.duplicate(true)
		_set_world(rows)

func bind_world(world: RefCounted, settings: Resource) -> PackedStringArray:
	if not _state.registry.is_empty(): return PackedStringArray([DeskLocalization.source("LOC_TRANSMISSION_HAS_STARTED_WORLD_GEOGRAPHY_CANNOT_BE_D0B074A3")])
	if world == null or settings == null or settings.countries.size() != rules.countries.size() or world.territories.size() != rules.countries.size(): return PackedStringArray([DeskLocalization.source("LOC_WORLD_COUNTRIES_DO_NOT_MATCH_THE_POPULATION_6EB8B327")])
	for index in settings.countries.size():
		if str(settings.countries[index].id) != str(rules.countries[index].id): return PackedStringArray([DeskLocalization.source("LOC_COUNTRY_ORDER_MISMATCH_F1FBCDD0")])
	var rows := _world_rows(world)
	_state.world_seed = int(world.seed_value)
	_geography_cache[rules.signature()+":"+str(world.seed_value)] = rows.duplicate(true)
	_set_world(rows)
	return PackedStringArray()

func _reference_world(seed_value: int) -> Array:
	var key: String = rules.signature()+":"+str(seed_value)
	if not _geography_cache.has(key):
		_geography_cache[key] = _world_rows(Generator.new().generate(rules.map_settings,seed_value))
	return _geography_cache[key].duplicate(true)

func _world_rows(world: RefCounted) -> Array:
	var rows: Array = []
	for index in rules.countries.size():
		var definition: Dictionary = rules.countries[index]
		var territory: RefCounted = world.territories[index]
		var neighbors: Array = []
		for neighbor in territory.neighbors: neighbors.append(str(rules.countries[neighbor].id))
		var distances: Array = []
		for other in rules.countries.size():
			if other != index and str(rules.countries[other].id) not in neighbors: distances.append({"id":str(rules.countries[other].id),"distance":territory.anchor.distance_to(world.territories[other].anchor)})
		distances.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.distance < b.distance)
		var contacts := {}
		for id in neighbors: contacts[id] = rules.land_contact
		for i in mini(rules.sea_neighbors,distances.size()): contacts[distances[i].id] = rules.sea_contact / (1.0 + distances[i].distance / rules.travel_distance_scale)
		rows.append({"id":str(definition.id),"population":int(definition.population),"population_source":str(definition.population_source),"area":territory.area,"anchor":[territory.anchor.x,territory.anchor.y],"land_neighbors":neighbors,"contacts":contacts})
	return rows

func _set_world(rows: Array) -> void:
	_state.world = rows.duplicate(true)
	_state.countries.clear()
	_state.populations.clear()
	_fitness_cache.clear()
	for row in rows:
		_state.countries[str(row.id)] = {"adopted":{},"exposed":{},"attention":{}}
		_state.populations[str(row.id)] = int(row.population)

func apply_populations(populations: Dictionary) -> void:
	assert(populations.size() == _state.world.size())
	for row: Dictionary in _state.world:
		var cid: String = str(row.id)
		var previous: int = _population(cid)
		var current: int = populations[cid]
		assert(current >= 0 and current <= previous)
		var country: Dictionary = _state.countries[cid]
		for field: String in ["adopted", "exposed", "attention"]:
			for id: String in country[field]:
				country[field][id] = floori(float(country[field][id]) * current / previous) if previous > 0 else 0
		if _sum(country.adopted) > current: country.adopted = _allocate(current, country.adopted)
		if _sum(country.exposed) > current: country.exposed = _cap_exposure(country.exposed, country.adopted, current)
		var budget: int = floori(current * rules.attention_fraction)
		if _sum(country.attention) > budget: country.attention = _allocate(budget, country.attention)
	_state.populations = populations.duplicate(true)
	_monitor_previous_scores.clear()

func has_country(id: String) -> bool:
	return _state.countries.has(id)

func adoption_pulse(variant_id: String, amount: float, country_id: String = "") -> int:
	var added := 0
	for row: Dictionary in _state.world:
		if not country_id.is_empty() and str(row.id) != country_id: continue
		var country: Dictionary = _state.countries[str(row.id)]
		var adopted := int(country.adopted.get(variant_id,0))
		var eligible := maxi(0,int(country.exposed.get(variant_id,0))-adopted)
		var increase := mini(floori(eligible*clampf(amount,0.0,1.0)),_population(str(row.id))-_sum(country.adopted))
		country.adopted[variant_id] = adopted+increase
		added += increase
	return added

func register(variant: Dictionary, profile: Dictionary, country_id: String, hour: int) -> void:
	if _state.registry.has(str(variant.id)): return
	var origin := country_id
	if not has_country(origin): origin = str(_state.world[posmod(str(variant.id).hash(),_state.world.size())].id)
	_state.registry[str(variant.id)] = {"birth_hour":hour,"origin_country":origin,"parent_ids":variant.parent_ids.duplicate(),"profile":profile.duplicate(true)}
	if str(variant.get("creator", "")) == "player" or not variant.get("origin_ids", []).is_empty():
		if str(variant.id) not in _state.propagation.lineage_ids: _state.propagation.lineage_ids.append(str(variant.id))
	for row in _state.world:
		var country: Dictionary = _state.countries[str(row.id)]
		for field in ["adopted","exposed","attention"]: country[field][str(variant.id)] = 0

func profile(draft: Dictionary) -> Dictionary:
	var source_draft := draft
	draft = ExpressionText.Community.effective_draft(draft)
	var channel: Resource = null
	var channel_id := str(draft.get("channel_id","local_board"))
	for item in catalog.channels:
		if str(item.id) == channel_id: channel = item
	var text := ""
	if ExpressionText.Composition.supports(str(draft.get("preset_id",""))):
		text = ExpressionText.render(catalog,source_draft)
	elif draft.get("slots") is Dictionary and not draft.slots.is_empty():
		for kernel in catalog.kernels:
			if str(kernel.id) == str(draft.get("kernel_id","")):
				for slot in kernel.required_slots: text += str(draft.slots.get(slot,"")) + " / "
	if text.is_empty(): text = str(draft.get("text",""))
	var distinct := {}
	for character in text: distinct[character] = true
	var expression: float = clampf(float(distinct.size()) / rules.expression_character_scale,rules.expression_floor,1.0)
	var skill_bonus := 0.0
	var skill_ids: Array[String] = []
	for value: Variant in draft.get("flow_skill_ids",[]):
		var skill_id := str(value)
		if skill_id in skill_ids: continue
		skill_ids.append(skill_id)
		skill_bonus += float(rules.skill_reach.get(skill_id,0.0))
	var result := {"language_id":str(draft.get("language_id","seowon")),"group_id":str(draft.get("group_id","culture_fans")),"topic_ids":Array(draft.get("topic_ids",[])),"political_known":bool(draft.get("political_known",false)),"political_position":_pair(draft.get("political_position",[])),"pragmatic_position":_pair(draft.get("pragmatic_position",[])),"language_access":float(draft.get("language_access",0.8)),"recognizability":float(draft.get("recognizability",0.8)),"context_dependency":float(draft.get("context_dependency",0.5)),"remix_cost":float(draft.get("remix_cost",0.3)),"reach":(float(channel.reach_factor) if channel != null else 1.0)*(1.0+skill_bonus),"channel_id":channel_id,"expression":expression,"text":text,"skill_ids":skill_ids}
	result.reach *= propagation_rules.Deviation.expression_factor(ExpressionText.patch_ids(draft).size(), skill_ids)
	for key in ["language_ids","group_ids"]:
		var values: Variant = draft.get(key,[])
		if values is Array and values.size() > 1: result[key] = values.duplicate()
	# Legacy author drafts already contain these bonuses; remove them before recalculating.
	for mark: Dictionary in draft.get("skill_effects",[]):
		for effect: Dictionary in mark.get("effects",[]):
			var field := str(effect.field)
			result[field] = clampf(float(result[field]) - float(effect.delta),0.0,1.0)
	for skill: Dictionary in catalog.DESIGN_RULES.skills:
		if str(skill.id) not in result.skill_ids: continue
		for effect: Dictionary in skill.get("draft_effects",[]):
			var field := str(effect.field)
			result[field] = clampf(float(result[field]) + float(effect.amount),0.0,1.0)
	result.propagation_meta = propagation_rules.metadata(result,draft)
	return result

func inherited_profile(variant: Dictionary, parent_id: String = "", profile_version: int = INHERITED_PROFILE_VERSION) -> Dictionary:
	if variant.get("flow_draft") is Dictionary:
		# The child draft contains its patch changes and the parent's unmodified skill inputs.
		var derived := profile(variant.flow_draft)
		derived.text = str(variant.text)
		var distinct := {}
		for character in str(variant.text): distinct[character] = true
		derived.expression = clampf(float(distinct.size()) / rules.expression_character_scale, rules.expression_floor, 1.0)
		if profile_version == 1: derived.reach = maxf(1.0,float(derived.reach))
		return derived
	var source: Dictionary = _state.registry.get(parent_id,{}).get("profile",{}).duplicate(true)
	if source.is_empty(): source = profile(variant)
	source.language_id = str(variant.language_id)
	source.erase("language_ids")
	source.topic_ids = Array(variant.get("topic_ids",[]))
	if variant.has("political_known"): source.political_known = bool(variant.political_known)
	if variant.has("political_position") and not variant.political_position.is_empty(): source.political_position = _pair(variant.political_position)
	if variant.has("pragmatic_position"): source.pragmatic_position = _pair(variant.pragmatic_position)
	source.text = str(variant.text)
	# Autonomous communities maintain their own expression, not the player's edit rights.
	source.expression = profile(variant).expression
	if not bool(variant.owned):
		source.language_access = rules.autonomous_language_access
		source.recognizability = rules.autonomous_recognizability
		source.context_dependency = rules.autonomous_context_dependency
		source.erase("group_ids")
		source.group_id = "culture_fans"
		for group: Resource in catalog.groups:
			if str(group.id) == str(variant.creator): source.group_id = str(group.id)
	source.reach = maxf(1.0,float(source.reach))
	return source

func _pair(value: Variant) -> Array:
	if value is Vector2: return [value.x,value.y]
	if value is Array and value.size() == 2: return value.duplicate()
	return [0.0,0.0]

func fitness(profile_data: Dictionary, country_id: String) -> Dictionary:
	var country: Dictionary = rules.country(country_id)
	var components := {}
	var delivery: Dictionary = propagation_rules.delivery(profile_data,country)
	components.language = float(delivery.language)
	components.group = _context_match(country.groups,profile_data,"group")
	var topic_score := 0.0
	for topic in profile_data.topic_ids: topic_score += float(country.topics.get(str(topic),0.0))
	components.topics = topic_score / maxf(1.0,profile_data.topic_ids.size())
	components.stance = _axis_match(profile_data.political_position,country.stance) if profile_data.political_known else 0.5
	components.pragmatic = _axis_match(profile_data.pragmatic_position,country.pragmatic)
	components.expression = float(profile_data.expression)
	var matched: float = _context_match(country.groups,profile_data,"group")
	components.access = float(profile_data.language_access) * float(profile_data.recognizability) * (1.0 - float(delivery.context_dependency) * (1.0 - matched)) * float(delivery.quality)
	var score := 0.0
	for key in components: score += float(components[key]) * float(rules.fitness_weights[key])
	return {"components":components,"score":clampf(score,0.01,1.0),"reach":float(profile_data.reach),"delivery":delivery}

func _context_match(distribution: Dictionary, profile_data: Dictionary, layer: String) -> float:
	var ids: Variant = profile_data.get(layer+"_ids",[str(profile_data.get(layer+"_id",""))])
	var result := 0.0
	if ids is Array:
		# Overlapping audiences are matched once; installed slots never add population.
		for id: Variant in ids: result = maxf(result,float(distribution.get(str(id),0.0)))
	return result

func active_topics(profile_data: Dictionary) -> PackedStringArray:
	return PackedStringArray(profile_data.get("topic_ids",[]))

func _axis_match(a: Array,b: Array) -> float:
	return clampf(1.0 - (absf(float(a[0])-float(b[0])) + absf(float(a[1])-float(b[1]))) / 4.0,0.0,1.0)

func _community_reuse(variant: Dictionary) -> float:
	if bool(variant.controlled) and not variant.has("mutation_parent_content"): return 1.0
	if not variant.get("flow_draft") is Dictionary:
		return float(variant.get("reuse_factor",1.0)) if bool(variant.owned) else 1.0
	var draft: Dictionary = variant.flow_draft
	var entry: Dictionary = _state.registry[str(variant.id)]
	var source: Dictionary = live_profile(str(variant.id))
	var required_slots := 0
	for kernel: MemeDemoKernel in catalog.kernels:
		if str(kernel.id) == str(draft.kernel_id): required_slots = kernel.required_slots.size()
	var baseline := EffectRules.reuse_factor(str(draft.reuse_permission),draft.replaceable_slots.size(),required_slots,
		float(source.remix_cost),float(source.context_dependency))
	return propagation_rules.community_reuse(source,draft,required_slots,baseline)

func _monitor_scores(variants: Array) -> Dictionary:
	var totals := {}
	for variant: Dictionary in variants: totals[str(variant.id)] = {"adopted":0, "exposed":0, "attention":0}
	var population := 0
	var budget := 0
	for row: Dictionary in _state.world:
		population += _population(str(row.id))
		budget += floori(_population(str(row.id)) * rules.attention_fraction)
		var country: Dictionary = _state.countries[str(row.id)]
		for id: String in totals:
			for field: String in ["adopted", "exposed", "attention"]:
				totals[id][field] += int(country[field].get(id, 0))
	var scores := {}
	for id: String in totals: scores[id] = MonitorMetrics.spread(totals[id], population, budget)
	return scores

func step(hour: int, variants: Array, modifier_factors: Dictionary) -> void:
	variants = active_variants(variants)
	_monitor_previous_scores = _monitor_scores(variants)
	_state.hour = hour
	var previous: Dictionary = _state.countries.duplicate(true)
	_plan_propagation(previous,variants,modifier_factors,hour)
	var reuse_factors := {}
	for variant: Dictionary in variants: reuse_factors[str(variant.id)] = _community_reuse(variant)
	for row: Dictionary in _state.world:
		var cid := str(row.id)
		var population := _population(cid)
		if population == 0: continue
		var weights := {}
		var fits := {}
		for variant: Dictionary in variants:
			var id := str(variant.id)
			var entry: Dictionary = _state.registry[id]
			var live_data: Dictionary = live_profile(id)
			var own: float = float(previous[cid].adopted[id]) / population
			var pressure := own + float(_state.propagation.pressure.get(cid,{}).get(id,0.0))
			var travel: float = rules.network_contact_multiplier if "network" in live_data.get("skill_ids",[]) else 1.0
			for neighbor in row.contacts:
				var neighbor_population := _population(str(neighbor))
				if neighbor_population > 0: pressure += float(previous[neighbor].adopted[id]) / neighbor_population * float(row.contacts[neighbor]) * travel
			if cid == str(entry.origin_country) and hour - int(entry.birth_hour) <= rules.seed_hours: pressure += rules.seed_pressure
			if hour-int(entry.birth_hour) <= rules.seed_hours:
				for parent_id in entry.parent_ids: pressure += float(previous[cid].adopted.get(parent_id,0))/population * rules.parent_relay
			if not _fitness_cache.has(id): _fitness_cache[id] = {}
			if not _fitness_cache[id].has(cid): _fitness_cache[id][cid] = fitness(live_data,cid)
			var fit: Dictionary = _fitness_cache[id][cid]
			fits[id] = fit.score
			var age: int = hour - int(entry.birth_hour)
			var refresh: float = rules.controlled_refresh_hours if bool(variant.controlled) else rules.community_refresh_hours
			var novelty: float = exp(-float(age) / refresh)
			var reuse: float = reuse_factors[id]
			var local_factors: Dictionary = modifier_factors.get(cid, modifier_factors)
			weights[id] = maxf(0.0,pressure * float(fit.score) * float(fit.reach) * novelty * reuse * float(local_factors.get(id,1.0)))
		var budget := floori(population * rules.attention_fraction)
		var demand := 0.0
		for value in weights.values(): demand += float(value)
		var activated_budget := floori(budget*clampf(demand*rules.attention_activation,0.0,1.0))
		var allocation := _allocate(activated_budget,weights)
		var next_adopted := {}
		var next_exposed := {}
		for variant: Dictionary in variants:
			var id := str(variant.id)
			var share: float = float(allocation.get(id,0)) / maxf(1.0,budget)
			var occupancy: float = clampf(float(fits[id]) * rules.occupancy_multiplier,0.0,rules.occupancy_cap)
			var target: float = population * share * occupancy
			next_adopted[id] = floori(lerpf(float(previous[cid].adopted[id]),target,rules.adoption_response))
			var exposure_target: float = population * share
			next_exposed[id] = maxi(int(next_adopted[id]),floori(lerpf(float(previous[cid].exposed[id]),exposure_target,rules.exposure_response)))
		# Variants are disjoint; adoption is a subset of that variant's exposure.
		if _sum(next_exposed) > population: next_exposed = _cap_exposure(next_exposed,next_adopted,population)
		for registered_id: String in _state.registry:
			if not next_adopted.has(registered_id):
				next_adopted[registered_id] = 0
				next_exposed[registered_id] = 0
				allocation[registered_id] = 0
		_state.countries[cid] = {"adopted":next_adopted,"exposed":next_exposed,"attention":allocation}

func _population(id: String) -> int:
	return int(_state.populations[id])

func _sum(data: Dictionary) -> int:
	var total := 0
	for value in data.values(): total += int(value)
	return total

func _allocate(total: int, weights: Dictionary) -> Dictionary:
	var result := {}
	var sum := 0.0
	for value in weights.values(): sum += float(value)
	var remainder: Array = []
	var used := 0
	for id in weights:
		var exact: float = total * float(weights[id]) / sum if sum > 0.0 else 0.0
		result[id] = floori(exact)
		used += int(result[id])
		remainder.append({"id":str(id),"fraction":exact-floorf(exact)})
	if sum > 0.0:
		remainder.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return a.fraction > b.fraction if a.fraction != b.fraction else a.id < b.id)
		for index in total-used: result[remainder[index].id] += 1
	return result

func _cap_exposure(exposed: Dictionary,adopted: Dictionary,population: int) -> Dictionary:
	var extra := {}
	for id in exposed: extra[id] = maxi(0,int(exposed[id])-int(adopted[id]))
	var allocated := _allocate(population-_sum(adopted),extra)
	for id in exposed: exposed[id] = int(adopted[id]) + int(allocated[id])
	return exposed

func record_publication(variants: Array, current_id: String, country_id: String, hour: int) -> void:
	_state.ending_progress = IndependentEndings.record_publication(_state.ending_progress, variants, current_id, country_id, hour, self)
	if not _state.ending_progress.is_empty(): _state.ending_evaluated_hour = int(_state.ending_progress.last_hour)

func record_author_edit(variants: Array, current_id: String, country_id: String, hour: int) -> void:
	_state.ending_progress = IndependentEndings.record_publication(_state.ending_progress, variants, current_id, country_id, hour, self, true)
	if not _state.ending_progress.is_empty(): _state.ending_evaluated_hour = int(_state.ending_progress.last_hour)

func evaluate_ending(variants: Array, hour: int, current_id: String = "", country_id: String = "") -> Dictionary:
	if not _state.victory.is_empty(): return _state.victory.duplicate(true)
	if current_id.is_empty(): current_id = str(_state.ending_progress.get("target_record_id", ""))
	if country_id.is_empty(): country_id = str(_state.ending_progress.get("country_id", ""))
	var result: Dictionary = IndependentEndings.evaluate(_state.ending_progress, variants, current_id, country_id, hour, self)
	if not _state.ending_progress.is_empty(): _state.ending_evaluated_hour = int(_state.ending_progress.last_hour)
	if not result.is_empty(): _state.victory = result.duplicate(true)
	return result

func snapshot(variants: Array, details: bool = true) -> Dictionary:
	variants = active_variants(variants)
	var world_population := 0
	for row in _state.world: world_population += _population(str(row.id))
	var totals := {}
	var attention := {"budget":0,"player":0,"external":0,"background":0}
	var country_rows: Array = []
	var exposed_total := 0
	for row: Dictionary in _state.world:
		var country: Dictionary = _state.countries[str(row.id)]
		var population := _population(str(row.id))
		var budget := floori(population*rules.attention_fraction)
		attention.budget += budget
		attention.background += budget-_sum(country.attention)
		var positions: Array = []
		for variant: Dictionary in variants:
			var id := str(variant.id)
			var adopted := int(country.adopted.get(id,0))
			var exposure := int(country.exposed.get(id,0))
			var slots := int(country.attention.get(id,0))
			if not totals.has(id): totals[id] = {"adopted":0,"exposed":0,"attention":0}
			totals[id].adopted += adopted
			totals[id].exposed += exposure
			totals[id].attention += slots
			attention["player" if variant.controlled else "external"] += slots
			if details: positions.append({"id":id,"meme_id":str(variant.get("meme_id", id)),"adopted":adopted,"exposed":exposure,"share":float(adopted)/maxf(1.0,population),"attention":slots})
		if details:
			var entry := row.duplicate(true)
			entry.initial_population = int(row.population)
			entry.population = population
			entry.variants = positions
			entry.unadopted = population-_sum(country.adopted)
			country_rows.append(entry)
		exposed_total += _sum(country.exposed)
	var variant_rows: Array = []
	var variants_by_id := {}
	var owned := 0
	var adopted_total := 0
	var lineage := 0
	var escaped := 0
	var controlled_lineage := 0
	var mutant := 0
	var autonomous_mutant := 0
	var controlled_mutant := 0
	for variant: Dictionary in variants:
		var id := str(variant.id)
		var counts: Dictionary = totals.get(id,{"adopted":0,"exposed":0,"attention":0})
		var is_lineage: bool = not variant.origin_ids.is_empty()
		var is_mutant: bool = is_lineage and not variant.parent_ids.is_empty() and not str(variant.get("source_event","")).is_empty() and str(variant.creator) != "player"
		adopted_total += int(counts.adopted)
		if variant.owned: owned += int(counts.adopted)
		if is_lineage:
			lineage += int(counts.adopted)
			if variant.controlled: controlled_lineage += int(counts.adopted)
			if not variant.controlled and not variant.owned: escaped += int(counts.adopted)
		if is_mutant:
			mutant += int(counts.adopted)
			if variant.controlled: controlled_mutant += int(counts.adopted)
			else: autonomous_mutant += int(counts.adopted)
		variant_rows.append({"id":id,"meme_id":str(variant.get("meme_id", id)),"meme_name":str(variant.get("meme_name", "")),"title":variant.text,"text":variant.text,"creator":variant.creator,"owned":variant.owned,"controlled":variant.controlled,"lineage":is_lineage,"mutation":is_mutant,"adopted":counts.adopted,"exposed":counts.exposed,"attention":counts.attention,"share":float(counts.adopted)/maxf(1.0,world_population),"origin_country":_state.registry.get(id,{}).get("origin_country",""),"source_event":variant.get("source_event",""),"source_presets":variant.get("source_presets",[]).duplicate(true)})
		var monitor_spread := MonitorMetrics.spread(counts, world_population, int(attention.budget))
		variant_rows.back().monitor_spread = monitor_spread
		variant_rows.back().monitor_growth = MonitorMetrics.growth(monitor_spread, float(_monitor_previous_scores.get(id, monitor_spread)))
		variants_by_id[id] = variant_rows.back().duplicate(true)
	return {"world_seed":_state.world_seed,"world_population":world_population,"countries":country_rows,"variants":variant_rows,"variants_by_id":variants_by_id,"owned_adopted":owned,"adopted":adopted_total,"exposed":exposed_total,"lineage_adopted":lineage,"escaped_adopted":escaped,"controlled_lineage_adopted":controlled_lineage,"mutant_adopted":mutant,"autonomous_mutant_adopted":autonomous_mutant,"controlled_mutant_adopted":controlled_mutant,"mutant_share":float(mutant)/maxf(1.0,world_population),"mutation_control_ratio":float(autonomous_mutant)/maxf(1.0,mutant),"owned_share":float(owned)/maxf(1.0,world_population),"lineage_share":float(lineage)/maxf(1.0,world_population),"escaped_share":float(escaped)/maxf(1.0,world_population),"unadopted_share":1.0-float(adopted_total)/maxf(1.0,world_population),"attention":attention,"equilibrium_days":float(_state.equilibrium_hours)/24.0,"ending_progress":_state.ending_progress.get("rows", []).duplicate(true),"victory":_state.victory.duplicate(true),"propagation":propagation_inspection(),"population_evidence":"configured_game_population","metric_explanation":DeskLocalization.source("LOC_EXPOSURE_IS_NOT_DOUBLE_COUNTED_ACROSS_VERSIONS_51B1D087"),"autonomy_explanation":DeskLocalization.source("LOC_THE_UNCONTROLLED_SHARE_COUNTS_ONLY_MUTANT_DESCENDANTS_A4F94F3A")}

func payload() -> Dictionary:
	return _state.duplicate(true)

func restore(data: Dictionary, variants: Array, hour: int) -> PackedStringArray:
	var errors := validate_payload(data,variants,hour)
	if errors.is_empty():
		_state = data.duplicate(true)
		_monitor_previous_scores.clear()
		_fitness_cache.clear()
	return errors

func validate_payload(data: Dictionary,variants: Array,hour: int) -> PackedStringArray:
	var errors := PackedStringArray()
	for variant: Variant in variants:
		if not variant is Dictionary or not variant.has_all(["id","family_id","parent_ids","origin_ids","creator","controlled","owned","text"]) or not variant.id is String or not variant.family_id is String or not variant.creator is String or not variant.text is String or not variant.parent_ids is Array or not variant.origin_ids is Array or not variant.controlled is bool or not variant.owned is bool: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_VERSION_FIELDS_OR_TYPES_976AE41C"))
		elif not _number(variant.get("semantic_distance")) or float(variant.semantic_distance) < 0.0 or float(variant.semantic_distance) > 1.0: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_SEMANTIC_DRIFT_8C39ABE4"))
	if not errors.is_empty(): return errors
	if not data.has_all(["competition_version","policy_signature","world_seed","world","populations","countries","registry","hour","active_seconds","hour_credit","ending_evaluated_hour","equilibrium_hours","equilibrium_candidate_hour","equilibrium_ranges","autonomous_hours","previous_shares","ending_progress","victory"]) or data.get("competition_version") != 1 or data.get("policy_signature") != rules.signature(): return PackedStringArray([DeskLocalization.source("LOC_COMPETITION_SAVE_RULES_MISMATCH_E5C4836F")])
	for key in ["world_seed","hour","ending_evaluated_hour","equilibrium_hours","autonomous_hours"]:
		if not _integer(data[key]) or int(data[key]) < 0: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_SAVE_INTEGER_572FEC0C")+key)
	if not _integer(data.equilibrium_candidate_hour) or int(data.equilibrium_candidate_hour) < -1: errors.append(DeskLocalization.source("LOC_INVALID_EQUILIBRIUM_WINDOW_START_TYPE_OR_RANGE_CECBB7B5"))
	for key in ["active_seconds","hour_credit"]:
		if not _number(data[key]) or float(data[key]) < 0.0: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_TIME_4A384748"))
	if _number(data.hour_credit) and float(data.hour_credit) >= 1.0: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_TIME_REMAINDER_C095A207"))
	for key in ["populations","countries","registry","previous_shares","equilibrium_ranges","ending_progress","victory"]:
		if not data[key] is Dictionary: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_SAVE_OBJECT_9BF60091")+key)
	if not data.world is Array or int(data.get("hour",-1)) != hour: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_CLOCK_OR_COUNTRY_TYPES_37C5A372"))
	if not errors.is_empty(): return errors
	var evaluated_hour := int(data.ending_evaluated_hour)
	if evaluated_hour > hour or int(data.equilibrium_hours) > evaluated_hour or int(data.autonomous_hours) > evaluated_hour: errors.append(DeskLocalization.source("LOC_COMPETITION_DURATION_CANNOT_EXCEED_RUNTIME_C26AEA8F"))
	if _canonical(data.world) != _canonical(_reference_world(int(data.world_seed))): errors.append(DeskLocalization.source("LOC_COMPETITION_COUNTRY_POPULATION_OR_GEOGRAPHY_HAS_BEEN_806CDA1E"))
	if data.populations.size() != rules.countries.size(): errors.append("Current population must cover every country")
	for row: Dictionary in rules.countries:
		var population: Variant = data.populations.get(str(row.id))
		if not _integer(population) or int(population) < 0 or int(population) > int(row.population): errors.append("Invalid current country population: " + str(row.id))
	if not errors.is_empty(): return errors
	var ids := {}
	for variant: Dictionary in variants:
		if ids.has(variant.id) or str(variant.id).is_empty(): errors.append(DeskLocalization.source("LOC_COMPETITION_VERSION_IDENTITY_IS_EMPTY_OR_DUPLICATED_3448340A"))
		ids[str(variant.id)] = variant
	if not _integer(data.equilibrium_candidate_hour) or int(data.equilibrium_candidate_hour) < -1 or int(data.equilibrium_candidate_hour) > evaluated_hour:
		errors.append(DeskLocalization.source("LOC_INVALID_EQUILIBRIUM_WINDOW_START_A44215B1"))
	elif int(data.equilibrium_candidate_hour) == -1:
		if int(data.equilibrium_hours) != 0 or not data.equilibrium_ranges.is_empty(): errors.append(DeskLocalization.source("LOC_AN_INACTIVE_EQUILIBRIUM_WINDOW_CANNOT_ACCUMULATE_TIME_46053AEC"))
	elif evaluated_hour-int(data.equilibrium_candidate_hour) != int(data.equilibrium_hours): errors.append(DeskLocalization.source("LOC_ACCUMULATED_EQUILIBRIUM_TIME_DOES_NOT_MATCH_THE_4FCBB4A2"))
	for id in data.equilibrium_ranges:
		var bounds: Variant = data.equilibrium_ranges[id]
		if id not in ["@lineage","@competitors"] and not ids.has(id): errors.append(DeskLocalization.source("LOC_EQUILIBRIUM_WINDOW_CONTAINS_AN_UNKNOWN_VERSION_F61D082A"))
		if not bounds is Dictionary or not _number(bounds.get("min")) or not _number(bounds.get("max")) or float(bounds.min) < 0.0 or float(bounds.max) > 1.0 or float(bounds.min) > float(bounds.max): errors.append(DeskLocalization.source("LOC_INVALID_EQUILIBRIUM_RANGE_553961BF"))
		elif float(bounds.max)-float(bounds.min) > rules.equilibrium_tolerance+0.000000000001: errors.append(DeskLocalization.source("LOC_EQUILIBRIUM_RANGE_EXCEEDS_CURRENT_RULES_F9133081"))
	if int(data.equilibrium_candidate_hour) >= 0 and not data.equilibrium_ranges.has_all(["@lineage","@competitors"]): errors.append(DeskLocalization.source("LOC_ACCUMULATED_RANGES_FOR_BOTH_EQUILIBRIUM_SIDES_ARE_8DA0898F"))
	var previous_total := 0.0
	for id in data.previous_shares:
		var share: Variant = data.previous_shares[id]
		if not ids.has(id) or not _number(share) or float(share) < 0.0 or float(share) > 1.0: errors.append(DeskLocalization.source("LOC_INVALID_HISTORICAL_COMPETITION_SHARES_47A0DDB2"))
		else: previous_total += float(share)
	if previous_total > 1.000000000001: errors.append(DeskLocalization.source("LOC_HISTORICAL_COMPETITION_SHARES_ARE_NOT_CONSERVED_AFF62254"))
	if evaluated_hour == 0 and (not data.previous_shares.is_empty() or int(data.equilibrium_candidate_hour) != -1 or int(data.autonomous_hours) != 0): errors.append("An unevaluated run cannot contain ending progress")
	if not errors.is_empty(): return errors
	var previous_lineage := 0.0
	var previous_mutants := 0.0
	var previous_controlled_mutants := 0.0
	for id: String in data.previous_shares:
		if not ids[id].origin_ids.is_empty(): previous_lineage += float(data.previous_shares[id])
		var variant: Dictionary = ids[id]
		if not variant.origin_ids.is_empty() and not variant.parent_ids.is_empty() and not str(variant.get("source_event", "")).is_empty() and str(variant.creator) != "player":
			previous_mutants += float(data.previous_shares[id])
			if variant.controlled: previous_controlled_mutants += float(data.previous_shares[id])
	var previous_competitors := maxf(0.0, previous_total - previous_lineage)
	if int(data.autonomous_hours) > 0 and (previous_mutants + 0.000000000001 < rules.autonomous_min_share or previous_controlled_mutants > 0.0): errors.append("Autonomous survival requires an uncontrolled mutant population")
	if int(data.equilibrium_candidate_hour) >= 0:
		if previous_lineage + 0.000000000001 < rules.equilibrium_min_side_share or previous_competitors + 0.000000000001 < rules.equilibrium_min_side_share: errors.append("An equilibrium window requires both sides to be present")
		for id: String in data.equilibrium_ranges:
			var share := previous_lineage if id == "@lineage" else (previous_competitors if id == "@competitors" else float(data.previous_shares.get(id, 0.0)))
			var bounds: Dictionary = data.equilibrium_ranges[id]
			if share < float(bounds.min) - 0.000000000001 or share > float(bounds.max) + 0.000000000001: errors.append("Equilibrium ranges must contain the last evaluated shares")
	if data.registry.size() != ids.size() or data.countries.size() != rules.countries.size(): errors.append(DeskLocalization.source("LOC_INCORRECT_COMPETITION_VERSION_OR_COUNTRY_COUNT_1EB4B504"))
	for id in data.registry:
		var entry: Variant = data.registry[id]
		if not ids.has(id) or not entry is Dictionary or not entry.get("profile") is Dictionary or not entry.get("parent_ids") is Array or not _integer(entry.get("birth_hour")) or int(entry.get("birth_hour",-1)) < 0 or int(entry.get("birth_hour",hour+1)) > hour or rules.country(str(entry.get("origin_country",""))).is_empty():
			errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_VERSION_SOURCE_B3378E3E"))
			continue
		var p: Dictionary = entry.profile
		errors.append_array(propagation_rules.validate_profile(p))
		if p.get("propagation_meta",{}).get("preset_id","") != str(ids[id].get("preset_id","")): errors.append("propagation: profile content identity mismatch")
		if _canonical(entry.parent_ids) != _canonical(ids[id].get("parent_ids",[])): errors.append(DeskLocalization.source("LOC_COMPETITION_PARENT_VERSION_CONFLICTS_WITH_ITS_LINEAGE_E744B567"))
		for key in ["language_access","recognizability","context_dependency","remix_cost","expression"]:
			if not _number(p.get(key)) or float(p.get(key,-1)) < 0.0 or float(p.get(key,2)) > 1.0: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_FIT_NUMERIC_VALUE_C134EA06"))
		if not _number(p.get("reach")) or float(p.get("reach",0)) <= 0.0 or not p.get("topic_ids") is Array or not p.get("skill_ids") is Array or not p.get("political_known") is bool: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_EXPRESSION_FIELDS_01708789"))
		for key in ["language_id","group_id","channel_id","text"]:
			if not p.get(key) is String: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_EXPRESSION_TEXT_TYPE_A6F4C14D"))
		if p.get("topic_ids") is Array:
			for topic in p.topic_ids:
				if topic not in catalog.topics: errors.append(DeskLocalization.source("LOC_UNREGISTERED_COMPETITION_TOPIC_A728B9AB"))
		if p.get("skill_ids") is Array:
			for skill in p.skill_ids:
				if skill not in rules.skill_reach: errors.append(DeskLocalization.source("LOC_UNREGISTERED_COMPETITION_ABILITY_3F326216"))
		for key in ["political_position","pragmatic_position"]:
			if not p.get(key) is Array or p[key].size() != 2: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_COORDINATES_C8C82B36"))
			else:
				for value in p[key]:
					if not _number(value) or absf(float(value)) > 1.0: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_COORDINATES_C8C82B36"))
	for row: Dictionary in rules.countries:
		var c: Variant = data.countries.get(str(row.id))
		if not c is Dictionary: errors.append(DeskLocalization.source("LOC_COMPETITION_COUNTRY_IS_MISSING_6701764F")); continue
		var valid := true
		for field in ["adopted","exposed","attention"]:
			if not c.get(field) is Dictionary or c[field].size() != ids.size(): valid = false; continue
			for id in c[field]:
				if not ids.has(id) or not _integer(c[field][id]) or int(c[field][id]) < 0: valid = false
		if not valid: errors.append(DeskLocalization.source("LOC_INVALID_COMPETITION_ALLOCATION_TYPE_OR_REFERENCE_CB369AD0")); continue
		var population := int(data.populations[str(row.id)])
		if _sum(c.adopted) > population or _sum(c.exposed) > population or _sum(c.attention) > floori(population*rules.attention_fraction): errors.append(DeskLocalization.source("LOC_COMPETITION_POPULATION_OR_ATTENTION_IS_NOT_CONSERVED_4A83A0A6"))
		for id in c.adopted:
			if int(c.adopted[id]) > int(c.exposed[id]): errors.append(DeskLocalization.source("LOC_ADOPTION_EXCEEDS_EXPOSURE_0A1A8E38"))
	if not errors.is_empty(): return errors
	var verifier: RefCounted = get_script().new(catalog)
	verifier._state = data.duplicate(true)
	errors.append_array(IndependentEndings.validate_state(data.ending_progress, variants, verifier, hour))
	if not data.ending_progress.is_empty() and int(data.ending_progress.get("last_hour", -1)) != evaluated_hour: errors.append("Ending progress and competition evaluation clocks must match")
	if errors.is_empty() and not data.victory.is_empty(): errors.append_array(IndependentEndings.validate_result(data.victory, data.ending_progress, variants, verifier, hour))
	errors.append_array(_validate_propagation_state(data.get("propagation"),data,ids,hour))
	return errors

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))

func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value: out[key] = _canonical(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(_canonical(item))
		return out
	if _number(value) and float(value) == floorf(float(value)): return int(value)
	return value

func active_variants(variants: Array) -> Array:
	var active: Array = []
	for raw: Dictionary in variants:
		if bool(raw.get("retired", false)): continue
		var visible := raw.duplicate(true)
		visible.merge(raw.get("effective_content", {}), true)
		visible.meme_id = str(raw.get("meme_id", raw.id))
		visible.meme_name = str(raw.get("meme_name", ""))
		active.append(visible)
	return active

func replace_revision(old_id: String, new_id: String) -> Dictionary:
	var error := _transfer_error(old_id, new_id)
	if not error.is_empty(): return {"error":error}
	for country: Dictionary in _state.countries.values():
		for field: String in ["adopted", "exposed", "attention"]:
			country[field][new_id] = int(country[field][old_id])
			country[field][old_id] = 0
	_state.registry[new_id].birth_hour = _state.registry[old_id].birth_hour
	_state.registry[new_id].origin_country = _state.registry[old_id].origin_country
	if _monitor_previous_scores.has(old_id):
		_monitor_previous_scores[new_id] = _monitor_previous_scores[old_id]
		_monitor_previous_scores.erase(old_id)
	for field: String in ["requests", "successful_contacts"]:
		var remapped := {}
		for record: Dictionary in _state.propagation[field].values():
			var updated := record.duplicate(true)
			if str(updated.variant_id) == old_id: updated.variant_id = new_id
			remapped[str(updated.variant_id)+"|"+str(updated.source)+"|"+str(updated.target)] = updated
		_state.propagation[field] = remapped
	_fitness_cache.erase(old_id)
	_fitness_cache.erase(new_id)
	return {"old_id":old_id, "new_id":new_id, "retained_ratio":1.0}

func split_revision(old_id: String, new_id: String, before_profile: Dictionary, rolled_profile: Dictionary) -> Dictionary:
	var error := _transfer_error(old_id, new_id)
	if not error.is_empty(): return {"error":error}
	var before := counterfactual_capability(old_id, before_profile)
	var after := counterfactual_capability(old_id, rolled_profile)
	var retained := clampf(after / before, 0.0, 1.0) if before > 0.0 else 1.0
	var transfers := {}
	for country_id: String in _state.countries:
		var country: Dictionary = _state.countries[country_id]
		var moved := {}
		for field: String in ["adopted", "exposed", "attention"]:
			var total := int(country[field][old_id])
			var remaining := roundi(float(total) * retained)
			country[field][old_id] = remaining
			country[field][new_id] = total - remaining
			moved[field] = total - remaining
		transfers[country_id] = moved
	_state.registry[old_id].effective_profile = rolled_profile.duplicate(true)
	_fitness_cache.erase(old_id)
	_fitness_cache.erase(new_id)
	return {"old_id":old_id, "new_id":new_id, "before_capability":before, "after_capability":after,
		"retained_ratio":retained, "new_ratio":1.0-retained, "transfers":transfers}

func counterfactual_capability(id: String, candidate_profile: Dictionary) -> float:
	var population := 0
	var budget := 0
	for row: Dictionary in _state.world:
		population += _population(str(row.id))
		budget += floori(_population(str(row.id)) * rules.attention_fraction)
	var capability := 0.0
	for row: Dictionary in _state.world:
		var cid := str(row.id)
		var country: Dictionary = _state.countries[cid]
		var counts := {"adopted":int(country.adopted.get(id, 0)), "exposed":int(country.exposed.get(id, 0)), "attention":int(country.attention.get(id, 0))}
		var fit := fitness(candidate_profile, cid)
		capability += MonitorMetrics.spread(counts, population, budget) * float(fit.score) * float(fit.reach)
	return capability

func _transfer_error(old_id: String, new_id: String) -> String:
	if old_id == new_id or not _state.registry.has(old_id) or not _state.registry.has(new_id):
		return "Meme transfer requires two distinct registered revisions"
	for country: Dictionary in _state.countries.values():
		for field: String in ["adopted", "exposed", "attention"]:
			if int(country[field].get(new_id, 0)) != 0: return "Meme transfer destination must be empty"
	return ""

func _empty_propagation_state() -> Dictionary:
	return {"schema":1,"content_signature":propagation_rules.signature(),"live_skill_ids":[],"lineage_ids":[],"last_hour":0,"requests":{},"successful_contacts":{},"hubs":{},"transfers":[],"pressure":{},"budget_total":0.0,"allocated_total":0.0,"last_exposed":{}}

func set_live_skills(skill_ids: Array, variants: Array) -> void:
	_state.propagation.live_skill_ids = skill_ids.duplicate()
	_state.propagation.lineage_ids = []
	for variant: Dictionary in variants:
		if str(variant.get("creator", "")) == "player" or not variant.get("origin_ids", []).is_empty():
			_state.propagation.lineage_ids.append(str(variant.id))
	_fitness_cache.clear()

func set_effective_profile(id: String, profile_data: Dictionary) -> void:
	_state.registry[id].effective_profile = profile_data.duplicate(true)
	_fitness_cache.erase(id)
	var runtime: Dictionary = _state.propagation
	runtime.hubs.erase(id)
	runtime.transfers = runtime.transfers.filter(func(record: Dictionary): return str(record.owner) != id)
	runtime.pressure = {}
	runtime.allocated_total = 0.0
	for transfer: Dictionary in runtime.transfers:
		var target := str(transfer.target)
		var variant_id := str(transfer.target_variant)
		if not runtime.pressure.has(target): runtime.pressure[target] = {}
		runtime.pressure[target][variant_id] = float(runtime.pressure[target].get(variant_id, 0.0)) + float(transfer.pressure)
		runtime.allocated_total += float(transfer.pressure)


func live_profile(id: String, state: Dictionary = {}) -> Dictionary:
	var world: Dictionary = _state if state.is_empty() else state
	var entry: Dictionary = world.registry.get(id, {})
	var result: Dictionary = entry.get("effective_profile", entry.get("profile", {})).duplicate(true)
	var runtime: Dictionary = world.get("propagation", {})
	if id in runtime.get("lineage_ids", []): result.skill_ids = runtime.get("live_skill_ids", []).duplicate()
	return result


func _country_row(id: String) -> Dictionary:
	for row: Dictionary in _state.world:
		if str(row.id) == id: return row
	return {}

func _published_groups(profile_data: Dictionary) -> Array:
	return profile_data.get("group_ids",[str(profile_data.group_id)]).duplicate()

func _landed(countries: Dictionary, variant_id: String, country_id: String) -> bool:
	return _population(country_id) > 0 and int(countries[country_id].adopted.get(variant_id,0)) >= maxi(1,ceili(float(_population(country_id))*0.000001))

func _has_hub_origin(variant_id: String, country_id: String, profile_data: Dictionary) -> bool:
	if str(_state.registry[variant_id].origin_country) == country_id: return true
	if "community_relay" not in profile_data.skill_ids: return false
	for entry: Dictionary in _state.propagation.successful_contacts.values():
		if str(entry.variant_id) == variant_id and str(entry.target) == country_id: return true
	return false

func _hub_groups(countries: Dictionary, variant_id: String, country_id: String, profile_data: Dictionary) -> Array:
	var result: Array = []
	if "community_hub" not in profile_data.skill_ids or not _landed(countries,variant_id,country_id) or not _has_hub_origin(variant_id,country_id,profile_data): return result
	var country: Dictionary = rules.country(country_id)
	for group: Variant in _published_groups(profile_data):
		if float(country.groups.get(str(group),0.0)) >= 0.25: result.append(str(group))
	return result

func _route_errors(source: String, target: String, variant_id: String, countries: Dictionary) -> PackedStringArray:
	if not _state.registry.has(variant_id) or not countries.has(source) or not countries.has(target) or source == target or _population(source) == 0 or _population(target) == 0: return PackedStringArray(["propagation: select a released meme and two different countries"])
	var p: Dictionary = live_profile(variant_id)
	var source_groups := _hub_groups(countries,variant_id,source,p)
	if source_groups.is_empty(): return PackedStringArray(["propagation: the source needs a landed community hub"])
	var row := _country_row(target)
	if not row.contacts.has(source): return PackedStringArray(["propagation: the selected directed contact does not exist"])
	var land: bool = source in row.land_neighbors
	if ("neighbor_forward" if land else "sea_forward") not in p.skill_ids: return PackedStringArray(["propagation: research the matching land or sea contact"])
	var target_groups: Dictionary = rules.country(target).groups
	var matched := false
	for group: Variant in source_groups: matched = matched or float(target_groups.get(str(group),0.0)) >= 0.25
	if not matched and "group_bridge" in p.skill_ids and _published_groups(p).size() >= 2:
		for group: Variant in _published_groups(p): matched = matched or float(target_groups.get(str(group),0.0)) >= 0.25
	if not matched: return PackedStringArray(["propagation: no published group connects these countries"])
	return PackedStringArray()

func configure_route(source_country: String, target_country: String, variant_id: String) -> PackedStringArray:
	var errors := _route_errors(source_country,target_country,variant_id,_state.countries)
	if not errors.is_empty(): return errors
	var requests: Dictionary = _state.propagation.requests.duplicate(true)
	var p: Dictionary = live_profile(variant_id)
	if "distributed_network" not in p.skill_ids:
		for key: String in requests.keys():
			if str(requests[key].variant_id) == variant_id: requests.erase(key)
	var key := variant_id+"|"+source_country+"|"+target_country
	requests[key] = {"variant_id":variant_id,"source":source_country,"target":target_country}
	_state.propagation.requests = requests
	return errors

func _cached_fitness(id: String, country_id: String) -> Dictionary:
	if not _fitness_cache.has(id): _fitness_cache[id] = {}
	if not _fitness_cache[id].has(country_id): _fitness_cache[id][country_id] = fitness(live_profile(id),country_id)
	return _fitness_cache[id][country_id]

func _transfer(owner: String, source_variant: String, target_variant: String, source: String, target: String, kind: String, weight: float) -> Dictionary:
	return {"owner":owner,"source_variant":source_variant,"target_variant":target_variant,"source":source,"target":target,"kind":kind,"weight":maxf(0.0,weight),"pressure":0.0}

func _plan_propagation(previous: Dictionary, variants: Array, modifiers: Dictionary, hour: int) -> void:
	var runtime: Dictionary = _state.propagation
	var candidates: Array[Dictionary] = []
	var by_id := {}
	var families := {}
	for variant: Dictionary in variants:
		by_id[str(variant.id)] = variant
		if variant.get("origin_ids",[]).is_empty(): continue
		var key := str(variant.origin_ids[0])
		if not families.has(key): families[key] = []
		families[key].append(str(variant.id))
	# A completed transfer creates a relay only after adoption is observed in its receiver.
	for transfer: Dictionary in runtime.transfers:
		if str(transfer.kind) != "community" or not _landed(previous,str(transfer.target_variant),str(transfer.target)): continue
		var key := str(transfer.target_variant)+"|"+str(transfer.source)+"|"+str(transfer.target)
		runtime.successful_contacts[key] = {"variant_id":str(transfer.target_variant),"source":str(transfer.source),"target":str(transfer.target),"hour":hour}
	runtime.hubs = {}
	for variant: Dictionary in variants:
		var id := str(variant.id)
		var p: Dictionary = live_profile(id)
		var skills: Array = p.skill_ids
		var hubs := {}
		for row: Dictionary in _state.world:
			var cid := str(row.id)
			var groups := _hub_groups(previous,id,cid,p)
			if not groups.is_empty(): hubs[cid] = groups
		if not hubs.is_empty(): runtime.hubs[id] = hubs
		var explicit: Array[Dictionary] = []
		for request: Dictionary in runtime.requests.values():
			if str(request.variant_id) == id: explicit.append(request)
		var community_candidates: Array[Dictionary] = []
		for source: String in hubs:
			for target_row: Dictionary in _state.world:
				var target := str(target_row.id)
				if not _route_errors(source,target,id,previous).is_empty(): continue
				var allowed := explicit.is_empty()
				for request: Dictionary in explicit: allowed = allowed or (request.source == source and request.target == target)
				if not allowed: continue
				var gap := 1.0-float(previous[target].adopted[id])/maxf(1.0,float(_population(target)))
				community_candidates.append(_transfer(id,id,id,source,target,"community",gap*float(previous[source].adopted[id])/maxf(1.0,float(_population(source)))))
		community_candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool: return float(a.weight)>float(b.weight))
		if "distributed_network" in skills: candidates.append_array(community_candidates)
		elif not community_candidates.is_empty(): candidates.append(community_candidates[0])
		if variant.get("origin_ids",[]).is_empty(): continue
		var siblings: Array = families.get(str(variant.origin_ids[0]),[])
		for row: Dictionary in _state.world:
			var cid := str(row.id)
			var gained := maxi(0,int(previous[cid].exposed[id])-int(runtime.last_exposed.get(cid,{}).get(id,0)))
			if "derivative_backlink" in skills and not bool(variant.controlled) and gained > 0:
				for parent_id: Variant in variant.parent_ids:
					if not by_id.has(str(parent_id)) or by_id[str(parent_id)].get("origin_ids",[]) != variant.origin_ids: continue
					candidates.append(_transfer(id,id,str(parent_id),cid,cid,"backlink",float(gained)/maxf(1.0,float(_population(cid)))))
			if not _landed(previous,id,cid): continue
			if "version_index" in skills and siblings.size() >= 2:
				var best := id
				var baseline := float(_cached_fitness(id,cid).score)
				var best_score := baseline
				for sibling: String in siblings:
					var score := float(_cached_fitness(sibling,cid).score)
					if score > best_score+0.000001:
						best = sibling
						best_score = score
				if best != id: candidates.append(_transfer(id,id,best,cid,cid,"index",best_score-baseline))
			if "template_archive" in skills and siblings.size() >= 2 and propagation_rules.can_template(p) and hour-int(_state.registry[id].birth_hour) >= 48 and int(previous[cid].attention.get(id,0)) < floori(float(previous[cid].adopted.get(id,0))*rules.attention_fraction):
				var local: Dictionary = modifiers.get(cid,modifiers)
				var demand := maxf(0.0,float(local.get(id,1.0))-1.0)
				for sibling: String in siblings:
					if sibling == id or bool(by_id[sibling].controlled): continue
					if int(previous[cid].exposed.get(sibling,0)) > int(runtime.last_exposed.get(cid,{}).get(sibling,0)): demand = maxf(demand,0.25)
				if demand > 0.0: candidates.append(_transfer(id,id,id,cid,cid,"archive",demand))
	var weight_by_owner := {}
	var pool_by_owner := {}
	for request: Dictionary in candidates:
		var owner := str(request.owner)
		weight_by_owner[owner] = float(weight_by_owner.get(owner,0.0))+float(request.weight)
		if pool_by_owner.has(owner): continue
		var adopted_pressure := 0.0
		for cid: String in previous: adopted_pressure += float(previous[cid].adopted.get(owner,0))/maxf(1.0,float(_population(cid)))
		pool_by_owner[owner] = minf(0.006,adopted_pressure*0.02)
	runtime.pressure = {}
	runtime.transfers = []
	runtime.budget_total = 0.0
	runtime.allocated_total = 0.0
	for pool: Variant in pool_by_owner.values(): runtime.budget_total += float(pool)
	for request: Dictionary in candidates:
		var owner := str(request.owner)
		var total := float(weight_by_owner[owner])
		var amount := float(pool_by_owner[owner])*float(request.weight)/total if total > 0.0 else 0.0
		if amount <= 0.0: continue
		request.pressure = amount
		runtime.transfers.append(request)
		var target := str(request.target)
		var target_id := str(request.target_variant)
		if not runtime.pressure.has(target): runtime.pressure[target] = {}
		runtime.pressure[target][target_id] = float(runtime.pressure[target].get(target_id,0.0))+amount
		runtime.allocated_total += amount
	runtime.last_exposed = {}
	for cid: String in previous: runtime.last_exposed[cid] = previous[cid].exposed.duplicate()
	runtime.last_hour = hour

func propagation_inspection() -> Dictionary:
	return _state.get("propagation",_empty_propagation_state()).duplicate(true)

func _validate_propagation_state(value: Variant, state: Dictionary, ids: Dictionary, hour: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if not value is Dictionary or not value.has_all(["schema","content_signature","live_skill_ids","lineage_ids","last_hour","requests","successful_contacts","hubs","transfers","pressure","budget_total","allocated_total","last_exposed"]): return PackedStringArray(["propagation: incomplete runtime"])
	if value.schema != 1 or value.content_signature != propagation_rules.signature() or not _integer(value.last_hour) or int(value.last_hour) < 0 or int(value.last_hour) > hour: errors.append("propagation: invalid runtime version or clock")
	for field: String in ["requests","successful_contacts","hubs","pressure","last_exposed"]:
		if not value[field] is Dictionary: errors.append("propagation: invalid runtime object "+field)
	if not value.transfers is Array: errors.append("propagation: invalid transfer list")
	if not value.live_skill_ids is Array or not value.lineage_ids is Array: errors.append("propagation: invalid live research state")
	else:
		var seen_skills := {}
		for skill: Variant in value.live_skill_ids:
			if not skill is String or skill not in rules.skill_reach or seen_skills.has(skill): errors.append("propagation: invalid live research ability")
			seen_skills[skill] = true
		var expected_lineage := {}
		for id: String in ids:
			if str(ids[id].get("creator", "")) == "player" or not ids[id].get("origin_ids", []).is_empty(): expected_lineage[id] = true
		var observed_lineage := {}
		for id: Variant in value.lineage_ids:
			if not id is String or not expected_lineage.has(id) or observed_lineage.has(id): errors.append("propagation: invalid live research lineage")
			observed_lineage[id] = true
		if expected_lineage.size() != observed_lineage.size(): errors.append("propagation: incomplete live research lineage")
	for field: String in ["budget_total","allocated_total"]:
		if not _number(value[field]) or float(value[field]) < 0.0: errors.append("propagation: invalid pressure budget")
	if not errors.is_empty(): return errors
	if float(value.allocated_total) > float(value.budget_total)+0.000000001: errors.append("propagation: pressure budget exceeded")
	var allocated := 0.0
	var pressure := {}
	var owner_spending := {}
	var eligible_owners := 0
	for id: String in ids:
		if not ids[id].get("origin_ids",[]).is_empty(): eligible_owners += 1
	if float(value.budget_total) > float(eligible_owners)*0.006+0.000000001: errors.append("propagation: source pressure budget is unbounded")
	for request: Variant in value.transfers:
		if not request is Dictionary or not request.has_all(["owner","source_variant","target_variant","source","target","kind","weight","pressure"]): errors.append("propagation: incomplete transfer"); continue
		if not ids.has(str(request.owner)) or not ids.has(str(request.source_variant)) or not ids.has(str(request.target_variant)) or not state.countries.has(str(request.source)) or not state.countries.has(str(request.target)) or request.kind not in ["community","backlink","index","archive"] or not _number(request.weight) or not _number(request.pressure) or float(request.weight) < 0.0 or float(request.pressure) <= 0.0: errors.append("propagation: invalid transfer provenance"); continue
		var owner := str(request.owner)
		if ids[owner].get("origin_ids",[]).is_empty(): errors.append("propagation: independent memes cannot spend player network pressure")
		if str(request.source_variant) != owner: errors.append("propagation: source owner mismatch")
		var source_profile: Dictionary = live_profile(owner,state)
		var skill: String = {"community":"community_hub","backlink":"derivative_backlink","index":"version_index","archive":"template_archive"}[str(request.kind)]
		if skill not in source_profile.skill_ids: errors.append("propagation: transfer ability was not researched")
		if request.kind == "community":
			var row := {}
			for world_row: Dictionary in state.world:
				if str(world_row.id) == str(request.target): row = world_row
			if str(request.source) not in row.contacts or owner != str(request.target_variant): errors.append("propagation: invalid community transfer edge")
			else:
				var edge_skill := "neighbor_forward" if str(request.source) in row.land_neighbors else "sea_forward"
				if edge_skill not in source_profile.skill_ids: errors.append("propagation: edge ability was not researched")
		elif request.kind == "backlink":
			if bool(ids[owner].controlled) or str(request.target_variant) not in ids[owner].parent_ids or ids[owner].origin_ids != ids[str(request.target_variant)].origin_ids: errors.append("propagation: backlink has no derivative source")
		elif request.kind == "index":
			if ids[owner].origin_ids != ids[str(request.target_variant)].origin_ids or owner == str(request.target_variant): errors.append("propagation: index contains an unrelated version")
		elif request.kind == "archive":
			if owner != str(request.target_variant) or not propagation_rules.can_template(source_profile) or hour-int(state.registry[owner].birth_hour) < 48: errors.append("propagation: invalid archive retrieval")
		owner_spending[owner] = float(owner_spending.get(owner,0.0))+float(request.pressure)
		if float(owner_spending[owner]) > 0.006+0.000000001: errors.append("propagation: one source copied its pressure budget")
		allocated += float(request.pressure)
		var key := str(request.target)+"|"+str(request.target_variant)
		pressure[key] = float(pressure.get(key,0.0))+float(request.pressure)
	var total := 0.0
	for cid: Variant in value.pressure:
		if not state.countries.has(str(cid)) or not value.pressure[cid] is Dictionary: errors.append("propagation: invalid pressure country"); continue
		for id: Variant in value.pressure[cid]:
			var amount: Variant = value.pressure[cid][id]
			if not ids.has(str(id)) or not _number(amount) or float(amount) < 0.0: errors.append("propagation: invalid pressure target"); continue
			if not is_equal_approx(float(amount),float(pressure.get(str(cid)+"|"+str(id),0.0))): errors.append("propagation: transfer allocation mismatch")
			total += float(amount)
	if not is_equal_approx(total,allocated) or not is_equal_approx(allocated,float(value.allocated_total)): errors.append("propagation: pressure is not conserved")
	for field: String in ["requests","successful_contacts"]:
		for record: Variant in value[field].values():
			if not record is Dictionary or not record.has_all(["variant_id","source","target"]) or not ids.has(str(record.get("variant_id",""))) or not state.countries.has(str(record.get("source",""))) or not state.countries.has(str(record.get("target",""))): errors.append("propagation: invalid directed contact"); continue
			var target := {}
			for row: Dictionary in state.world:
				if str(row.id) == str(record.target): target = row
			if not target.get("contacts",{}).has(str(record.source)): errors.append("propagation: contact does not follow world geography")
			if field == "successful_contacts" and (not _integer(record.get("hour")) or int(record.hour) < 0 or int(record.hour) > hour): errors.append("propagation: invalid successful contact hour")
	for cid: Variant in value.last_exposed:
		if not state.countries.has(str(cid)) or not value.last_exposed[cid] is Dictionary: errors.append("propagation: invalid observed exposure country"); continue
		for id: Variant in value.last_exposed[cid]:
			if not ids.has(str(id)) or not _integer(value.last_exposed[cid][id]) or int(value.last_exposed[cid][id]) < 0 or int(value.last_exposed[cid][id]) > int(rules.country(str(cid)).population): errors.append("propagation: invalid observed exposure")
	for id: Variant in value.hubs:
		if not ids.has(str(id)) or not value.hubs[id] is Dictionary: errors.append("propagation: invalid hub owner"); continue
		var p: Dictionary = live_profile(str(id),state)
		for cid: Variant in value.hubs[id]:
			if not state.countries.has(str(cid)) or not value.hubs[id][cid] is Array: errors.append("propagation: invalid hub country"); continue
			for group: Variant in value.hubs[id][cid]:
				if group not in _published_groups(p) or float(rules.country(str(cid)).groups.get(str(group),0.0)) < 0.25: errors.append("propagation: hub group was not published")
	return errors
