extends RefCounted

const Generator = preload("res://scripts/gameplay/map/map_generator.gd")
static var _geography_cache: Dictionary = {}
var rules: MemeGameplayRules
var catalog: MemeDemoCatalog
var _state: Dictionary = {}
var _fitness_cache: Dictionary = {}
var _populations: Dictionary = {}

func _init(content: MemeDemoCatalog = null) -> void:
	catalog = content
	if content != null: rules = content.gameplay_rules

func reset() -> void:
	_fitness_cache.clear()
	_state = {"competition_version":1,"policy_signature":rules.signature(),"world_seed":rules.reference_geometry_seed,"world":[],"countries":{},"registry":{},"hour":0,"active_seconds":0.0,"hour_credit":0.0,"equilibrium_hours":0,"equilibrium_candidate_hour":-1,"equilibrium_ranges":{},"autonomous_hours":0,"previous_shares":{},"victory":{}}
	_set_world(_reference_world(int(rules.reference_geometry_seed)))

func bind_world(world: RefCounted, settings: Resource) -> PackedStringArray:
	if not _state.registry.is_empty(): return PackedStringArray(["已开始传播，不能替换世界地理。"])
	if world == null or settings == null or settings.countries.size() != rules.countries.size() or world.territories.size() != rules.countries.size(): return PackedStringArray(["世界国家与人口规则不匹配。"])
	for index in settings.countries.size():
		if str(settings.countries[index].id) != str(rules.countries[index].id): return PackedStringArray(["国家顺序不匹配。"])
	var rows := _world_rows(world)
	if _canonical(rows) != _canonical(_reference_world(int(world.seed_value))): return PackedStringArray(["世界地理与当前传播规则不一致。"])
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
	_populations.clear()
	_fitness_cache.clear()
	for row in rows:
		_state.countries[str(row.id)] = {"adopted":{},"exposed":{},"attention":{}}
		_populations[str(row.id)] = int(row.population)

func has_country(id: String) -> bool:
	return _state.countries.has(id)

func adoption_pulse(variant_id: String, amount: float) -> int:
	var added := 0
	for row: Dictionary in _state.world:
		var country: Dictionary = _state.countries[str(row.id)]
		var adopted := int(country.adopted.get(variant_id,0))
		var eligible := maxi(0,int(country.exposed.get(variant_id,0))-adopted)
		var increase := mini(floori(eligible*clampf(amount,0.0,1.0)),int(row.population)-_sum(country.adopted))
		country.adopted[variant_id] = adopted+increase
		added += increase
	return added

func register(variant: Dictionary, profile: Dictionary, country_id: String, hour: int) -> void:
	if _state.registry.has(str(variant.id)): return
	var origin := country_id
	if not has_country(origin): origin = str(_state.world[posmod(str(variant.id).hash(),_state.world.size())].id)
	_state.registry[str(variant.id)] = {"birth_hour":hour,"origin_country":origin,"parent_ids":variant.parent_ids.duplicate(),"profile":profile.duplicate(true)}
	for row in _state.world:
		var country: Dictionary = _state.countries[str(row.id)]
		for field in ["adopted","exposed","attention"]: country[field][str(variant.id)] = 0

func profile(draft: Dictionary) -> Dictionary:
	var channel: Resource = null
	var channel_id := str(draft.get("channel_id","local_board"))
	for item in catalog.channels:
		if str(item.id) == channel_id: channel = item
	var text := ""
	if draft.get("slots") is Dictionary and not draft.slots.is_empty():
		for kernel in catalog.kernels:
			if str(kernel.id) == str(draft.get("kernel_id","")):
				for slot in kernel.required_slots: text += str(draft.slots.get(slot,"")) + " / "
	if text.is_empty(): text = str(draft.get("text",""))
	var distinct := {}
	for character in text: distinct[character] = true
	var expression: float = clampf(float(distinct.size()) / rules.expression_character_scale,rules.expression_floor,1.0)
	var skill_bonus := 0.0
	for skill_id in draft.get("flow_skill_ids",[]): skill_bonus += float(rules.skill_reach.get(str(skill_id),0.0))
	var attachment := {}
	var saved: Dictionary = draft.get("context_layer_attachment",{}) if draft.get("context_layer_attachment",{}) is Dictionary else {}
	for layer in ["language","group","topics","stance","pragmatic"]: attachment[layer] = bool(saved.get(layer,true))
	var result := {"language_id":str(draft.get("language_id","mixed")),"group_id":str(draft.get("group_id","culture_fans")),"topic_ids":Array(draft.get("topic_ids",[])),"political_known":bool(draft.get("political_known",false)),"political_position":_pair(draft.get("political_position",[])),"pragmatic_position":_pair(draft.get("pragmatic_position",[])),"language_access":float(draft.get("language_access",0.8)),"recognizability":float(draft.get("recognizability",0.8)),"context_dependency":float(draft.get("context_dependency",0.5)),"remix_cost":float(draft.get("remix_cost",0.3)),"reach":(float(channel.reach_factor) if channel != null else 1.0)*(1.0+skill_bonus),"channel_id":channel_id,"expression":expression,"text":text,"skill_ids":Array(draft.get("flow_skill_ids",[])),"context_layer_attachment":attachment}
	for key in ["language_ids","group_ids"]:
		var values: Variant = draft.get(key,[])
		if values is Array and values.size() > 1: result[key] = values.duplicate()
	return result

func inherited_profile(variant: Dictionary, parent_id: String = "") -> Dictionary:
	var source: Dictionary = _state.registry.get(parent_id,{}).get("profile",{}).duplicate(true)
	if source.is_empty(): source = profile(variant)
	source.language_id = str(variant.language_id)
	source.erase("language_ids")
	source.topic_ids = Array(variant.get("topic_ids",[]))
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
		source.group_id = str(variant.creator) if str(variant.creator) in ["commuters","students","culture_fans"] else "culture_fans"
	source.reach = maxf(1.0,float(source.reach))
	return source

func _pair(value: Variant) -> Array:
	if value is Vector2: return [value.x,value.y]
	if value is Array and value.size() == 2: return value.duplicate()
	return [0.0,0.0]

func fitness(profile_data: Dictionary, country_id: String) -> Dictionary:
	var country: Dictionary = rules.country(country_id)
	var components := {}
	components.language = _context_match(country.languages,profile_data,"language") if attached(profile_data,"language") else 0.5
	components.group = _context_match(country.groups,profile_data,"group") if attached(profile_data,"group") else 0.5
	var topic_score := 0.0
	for topic in profile_data.topic_ids: topic_score += float(country.topics.get(str(topic),0.08))
	components.topics = topic_score / maxf(1.0,profile_data.topic_ids.size()) if attached(profile_data,"topics") else 0.5
	components.stance = _axis_match(profile_data.political_position,country.stance) if profile_data.political_known and attached(profile_data,"stance") else 0.5
	components.pragmatic = _axis_match(profile_data.pragmatic_position,country.pragmatic) if attached(profile_data,"pragmatic") else 0.5
	components.expression = float(profile_data.expression)
	var matched: float = _context_match(country.groups,profile_data,"group") if attached(profile_data,"group") else 0.5
	components.access = float(profile_data.language_access) * float(profile_data.recognizability) * (1.0 - float(profile_data.context_dependency) * (1.0 - matched))
	var score := 0.0
	for key in components: score += float(components[key]) * float(rules.fitness_weights[key])
	return {"components":components,"score":clampf(score,0.01,1.0),"reach":float(profile_data.reach)}

func _context_match(distribution: Dictionary, profile_data: Dictionary, layer: String) -> float:
	var ids: Variant = profile_data.get(layer+"_ids",[str(profile_data.get(layer+"_id",""))])
	var result := 0.0
	if ids is Array:
		# Overlapping audiences are matched once; installed slots never add population.
		for id: Variant in ids: result = maxf(result,float(distribution.get(str(id),0.15)))
	return result

func attached(profile_data: Dictionary,layer: String) -> bool:
	return bool(profile_data.get("context_layer_attachment",{}).get(layer,true))

func active_topics(profile_data: Dictionary) -> PackedStringArray:
	return PackedStringArray(profile_data.get("topic_ids",[])) if attached(profile_data,"topics") else PackedStringArray()

func _axis_match(a: Array,b: Array) -> float:
	return clampf(1.0 - (absf(float(a[0])-float(b[0])) + absf(float(a[1])-float(b[1]))) / 4.0,0.0,1.0)

func step(hour: int, variants: Array, modifier_factors: Dictionary) -> void:
	_state.hour = hour
	var previous: Dictionary = _state.countries.duplicate(true)
	for row: Dictionary in _state.world:
		var cid := str(row.id)
		var population := int(row.population)
		var weights := {}
		var fits := {}
		for variant: Dictionary in variants:
			var id := str(variant.id)
			var entry: Dictionary = _state.registry[id]
			var own: float = float(previous[cid].adopted[id]) / population
			var pressure := own
			var travel: float = rules.network_contact_multiplier if "network" in entry.profile.get("skill_ids",[]) else 1.0
			for neighbor in row.contacts: pressure += float(previous[neighbor].adopted[id]) / float(_population(str(neighbor))) * float(row.contacts[neighbor]) * travel
			if cid == str(entry.origin_country) and hour - int(entry.birth_hour) <= rules.seed_hours: pressure += rules.seed_pressure
			if hour-int(entry.birth_hour) <= rules.seed_hours:
				for parent_id in entry.parent_ids: pressure += float(previous[cid].adopted.get(parent_id,0))/population * rules.parent_relay
			if not _fitness_cache.has(id): _fitness_cache[id] = {}
			if not _fitness_cache[id].has(cid): _fitness_cache[id][cid] = fitness(entry.profile,cid)
			var fit: Dictionary = _fitness_cache[id][cid]
			fits[id] = fit.score
			var age: int = hour - int(entry.birth_hour)
			var refresh: float = rules.controlled_refresh_hours if bool(variant.controlled) else rules.community_refresh_hours
			var novelty: float = exp(-float(age) / refresh)
			var reuse: float = float(variant.get("reuse_factor",1.0)) if not bool(variant.controlled) and bool(variant.owned) else 1.0
			weights[id] = maxf(0.0,pressure * float(fit.score) * float(fit.reach) * novelty * reuse * float(modifier_factors.get(id,1.0)))
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
		_state.countries[cid] = {"adopted":next_adopted,"exposed":next_exposed,"attention":allocation}
	_update_victory(variants)

func _population(id: String) -> int:
	return int(_populations[id])

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

func _update_victory(variants: Array) -> void:
	var view := snapshot(variants,false)
	var shares := {}
	var values := {"@lineage":float(view.lineage_share),"@competitors":maxf(0.0,1.0-float(view.unadopted_share)-float(view.lineage_share))}
	for row: Dictionary in view.variants:
		shares[row.id] = row.share
		if float(row.share) >= rules.equilibrium_variant_min_share or _state.equilibrium_ranges.has(row.id): values[row.id] = float(row.share)
	var qualified: bool = float(values["@lineage"]) >= rules.equilibrium_min_side_share and float(values["@competitors"]) >= rules.equilibrium_min_side_share
	var ranges: Dictionary = _state.equilibrium_ranges.duplicate(true)
	var bounded := true
	for id in values:
		var previous: Dictionary = ranges.get(id,{"min":values[id],"max":values[id]})
		ranges[id] = {"min":minf(float(previous.min),float(values[id])),"max":maxf(float(previous.max),float(values[id]))}
		bounded = bounded and float(ranges[id].max)-float(ranges[id].min) <= rules.equilibrium_tolerance
	if not qualified or int(_state.equilibrium_candidate_hour) < 0 or not bounded:
		_state.equilibrium_candidate_hour = int(_state.hour) if qualified else -1
		_state.equilibrium_ranges = {}
		for id in values: _state.equilibrium_ranges[id] = {"min":values[id],"max":values[id]}
		_state.equilibrium_hours = 0
	else:
		_state.equilibrium_ranges = ranges
		_state.equilibrium_hours = int(_state.hour)-int(_state.equilibrium_candidate_hour)
	_state.previous_shares = shares
	var autonomous: bool = view.mutant_adopted > 0 and view.controlled_mutant_adopted == 0 and view.autonomous_mutant_adopted == view.mutant_adopted and view.mutant_share >= rules.autonomous_min_share
	_state.autonomous_hours = int(_state.autonomous_hours)+1 if autonomous else 0
	var eligibility := _eligibility(view,int(_state.hour),int(_state.autonomous_hours),int(_state.equilibrium_hours))
	if not eligibility.ids.is_empty() and _state.victory.is_empty(): _state.victory = {"id":eligibility.ids[0],"eligible_ids":eligibility.ids,"hour":_state.hour,"owned_share":view.owned_share,"lineage_share":view.lineage_share,"escaped_share":view.escaped_share,"mutant_share":view.mutant_share,"mutation_control_ratio":float(view.autonomous_mutant_adopted)/maxf(1.0,view.mutant_adopted),"distinct_variants":eligibility.distinct,"equilibrium_hours":_state.equilibrium_hours,"autonomous_hours":_state.autonomous_hours}

func _eligibility(view: Dictionary,hour: int,autonomous_hours: int,equilibrium_hours: int) -> Dictionary:
	var ids: Array = []
	if view.owned_share >= rules.ownership_victory_share: ids.append("own_world")
	if view.mutant_adopted > 0 and view.controlled_mutant_adopted == 0 and view.mutant_share >= rules.autonomous_min_share and autonomous_hours >= rules.autonomous_survival_hours: ids.append("autonomous_lineage")
	var external_share: float = maxf(0.0,1.0-view.lineage_share-view.unadopted_share)
	if hour >= rules.equilibrium_min_hours and equilibrium_hours >= rules.equilibrium_window_hours and view.lineage_share >= rules.equilibrium_min_side_share and external_share >= rules.equilibrium_min_side_share: ids.append("competitor_equilibrium")
	var distinct := 0
	for row: Dictionary in view.variants:
		if row.lineage and row.share >= rules.distinct_variant_min_share: distinct += 1
	if distinct >= 2 and view.lineage_share >= rules.lineage_victory_share: ids.append("lineage_diversity")
	return {"ids":ids,"distinct":distinct}

func snapshot(variants: Array, details: bool = true) -> Dictionary:
	var world_population := 0
	for row in _state.world: world_population += int(row.population)
	var totals := {}
	var attention := {"budget":0,"player":0,"external":0,"background":0}
	var country_rows: Array = []
	var exposed_total := 0
	for row: Dictionary in _state.world:
		var country: Dictionary = _state.countries[str(row.id)]
		var budget := floori(int(row.population)*rules.attention_fraction)
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
			if details: positions.append({"id":id,"family_id":variant.family_id,"adopted":adopted,"exposed":exposure,"share":float(adopted)/int(row.population),"attention":slots})
		if details:
			var entry := row.duplicate(true)
			entry.variants = positions
			entry.unadopted = int(row.population)-_sum(country.adopted)
			country_rows.append(entry)
		exposed_total += _sum(country.exposed)
	var variant_rows: Array = []
	var variants_by_id := {}
	var family_rows := {}
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
		variant_rows.append({"id":id,"family_id":variant.family_id,"title":variant.text,"text":variant.text,"creator":variant.creator,"owned":variant.owned,"controlled":variant.controlled,"lineage":is_lineage,"mutation":is_mutant,"adopted":counts.adopted,"exposed":counts.exposed,"attention":counts.attention,"share":float(counts.adopted)/maxf(1.0,world_population),"origin_country":_state.registry.get(id,{}).get("origin_country",""),"source_event":variant.get("source_event",""),"source_presets":variant.get("source_presets",[]).duplicate(true)})
		variants_by_id[id] = variant_rows.back().duplicate(true)
		var family_id := str(variant.family_id)
		if not family_rows.has(family_id): family_rows[family_id] = {"id":family_id,"adopted":0,"share":0.0,"variant_ids":[]}
		family_rows[family_id].adopted += int(counts.adopted)
		family_rows[family_id].share = float(family_rows[family_id].adopted)/maxf(1.0,world_population)
		family_rows[family_id].variant_ids.append(id)
	return {"world_seed":_state.world_seed,"world_population":world_population,"countries":country_rows,"variants":variant_rows,"variants_by_id":variants_by_id,"families_by_id":family_rows,"owned_adopted":owned,"adopted":adopted_total,"exposed":exposed_total,"lineage_adopted":lineage,"escaped_adopted":escaped,"controlled_lineage_adopted":controlled_lineage,"mutant_adopted":mutant,"autonomous_mutant_adopted":autonomous_mutant,"controlled_mutant_adopted":controlled_mutant,"mutant_share":float(mutant)/maxf(1.0,world_population),"mutation_control_ratio":float(autonomous_mutant)/maxf(1.0,mutant),"owned_share":float(owned)/maxf(1.0,world_population),"lineage_share":float(lineage)/maxf(1.0,world_population),"escaped_share":float(escaped)/maxf(1.0,world_population),"unadopted_share":1.0-float(adopted_total)/maxf(1.0,world_population),"attention":attention,"equilibrium_days":float(_state.equilibrium_hours)/24.0,"victory":_state.victory.duplicate(true),"population_evidence":"configured_game_population","metric_explanation":"不同版本的曝光不重复，采用是对应曝光的子集；未采用人口不计为竞争模因。","autonomy_explanation":"失控比例只统计真实事件产生的变异后代，排除原始投放与玩家再创作；作者归属与控制权分别记录。"}

func payload() -> Dictionary:
	return _state.duplicate(true)

func restore(data: Dictionary, variants: Array, hour: int) -> PackedStringArray:
	var errors := validate_payload(data,variants,hour)
	if errors.is_empty():
		_state = data.duplicate(true)
		_fitness_cache.clear()
		_populations.clear()
		for row: Dictionary in _state.world: _populations[str(row.id)] = int(row.population)
	return errors

func validate_payload(data: Dictionary,variants: Array,hour: int) -> PackedStringArray:
	var errors := PackedStringArray()
	for variant: Variant in variants:
		if not variant is Dictionary or not variant.has_all(["id","family_id","parent_ids","origin_ids","creator","controlled","owned","text"]) or not variant.id is String or not variant.family_id is String or not variant.creator is String or not variant.text is String or not variant.parent_ids is Array or not variant.origin_ids is Array or not variant.controlled is bool or not variant.owned is bool: errors.append("竞争版本字段或类型非法。")
		elif not _number(variant.get("semantic_distance")) or float(variant.semantic_distance) < 0.0 or float(variant.semantic_distance) > 1.0: errors.append("竞争语义偏移非法。")
	if not errors.is_empty(): return errors
	if not data.has_all(["competition_version","policy_signature","world_seed","world","countries","registry","hour","active_seconds","hour_credit","equilibrium_hours","equilibrium_candidate_hour","equilibrium_ranges","autonomous_hours","previous_shares","victory"]) or data.get("competition_version") != 1 or data.get("policy_signature") != rules.signature(): return PackedStringArray(["竞争存档规则不匹配。"])
	for key in ["world_seed","hour","equilibrium_hours","autonomous_hours"]:
		if not _integer(data[key]) or int(data[key]) < 0: errors.append("竞争存档整数非法："+key)
	if not _integer(data.equilibrium_candidate_hour) or int(data.equilibrium_candidate_hour) < -1: errors.append("均衡窗口起点类型或范围非法。")
	for key in ["active_seconds","hour_credit"]:
		if not _number(data[key]) or float(data[key]) < 0.0: errors.append("竞争时间非法。")
	if _number(data.hour_credit) and float(data.hour_credit) >= 1.0: errors.append("竞争时间余额非法。")
	for key in ["countries","registry","previous_shares","equilibrium_ranges","victory"]:
		if not data[key] is Dictionary: errors.append("竞争存档对象非法："+key)
	if not data.world is Array or int(data.get("hour",-1)) != hour: errors.append("竞争时钟或国家类型非法。")
	if not errors.is_empty(): return errors
	if int(data.equilibrium_hours) > hour or int(data.autonomous_hours) > hour: errors.append("竞争持续时间不能超过运行时间。")
	if _canonical(data.world) != _canonical(_reference_world(int(data.world_seed))): errors.append("竞争国家人口或地理已被修改。")
	var ids := {}
	for variant: Dictionary in variants:
		if ids.has(variant.id) or str(variant.id).is_empty(): errors.append("竞争版本身份重复或为空。")
		ids[str(variant.id)] = variant
	if not _integer(data.equilibrium_candidate_hour) or int(data.equilibrium_candidate_hour) < -1 or int(data.equilibrium_candidate_hour) > hour:
		errors.append("均衡窗口起点非法。")
	elif int(data.equilibrium_candidate_hour) == -1:
		if int(data.equilibrium_hours) != 0: errors.append("未启动的均衡窗口不能累计时间。")
	elif hour-int(data.equilibrium_candidate_hour) != int(data.equilibrium_hours): errors.append("均衡累计时间与实际窗口不一致。")
	for id in data.equilibrium_ranges:
		var bounds: Variant = data.equilibrium_ranges[id]
		if id not in ["@lineage","@competitors"] and not ids.has(id): errors.append("均衡窗口包含未知版本。")
		if not bounds is Dictionary or not _number(bounds.get("min")) or not _number(bounds.get("max")) or float(bounds.min) < 0.0 or float(bounds.max) > 1.0 or float(bounds.min) > float(bounds.max): errors.append("均衡范围非法。")
		elif float(bounds.max)-float(bounds.min) > rules.equilibrium_tolerance+0.000000000001: errors.append("均衡范围超过当前规则。")
	if int(data.equilibrium_candidate_hour) >= 0 and not data.equilibrium_ranges.has_all(["@lineage","@competitors"]): errors.append("均衡双方累计范围缺失。")
	var previous_total := 0.0
	for id in data.previous_shares:
		var share: Variant = data.previous_shares[id]
		if not ids.has(id) or not _number(share) or float(share) < 0.0 or float(share) > 1.0: errors.append("竞争历史占比非法。")
		else: previous_total += float(share)
	if previous_total > 1.000000000001: errors.append("竞争历史占比不守恒。")
	if data.registry.size() != ids.size() or data.countries.size() != rules.countries.size(): errors.append("竞争版本或国家数量错误。")
	for id in data.registry:
		var entry: Variant = data.registry[id]
		if not ids.has(id) or not entry is Dictionary or not entry.get("profile") is Dictionary or not entry.get("parent_ids") is Array or not _integer(entry.get("birth_hour")) or int(entry.get("birth_hour",-1)) < 0 or int(entry.get("birth_hour",hour+1)) > hour or rules.country(str(entry.get("origin_country",""))).is_empty():
			errors.append("竞争版本来源非法。")
			continue
		var p: Dictionary = entry.profile
		if _canonical(entry.parent_ids) != _canonical(ids[id].get("parent_ids",[])): errors.append("竞争父版本与谱系不一致。")
		for key in ["language_access","recognizability","context_dependency","remix_cost","expression"]:
			if not _number(p.get(key)) or float(p.get(key,-1)) < 0.0 or float(p.get(key,2)) > 1.0: errors.append("竞争适配数值非法。")
		if not _number(p.get("reach")) or float(p.get("reach",0)) <= 0.0 or not p.get("topic_ids") is Array or not p.get("skill_ids") is Array or not p.get("political_known") is bool: errors.append("竞争表达字段非法。")
		for key in ["language_id","group_id","channel_id","text"]:
			if not p.get(key) is String: errors.append("竞争表达文本类型非法。")
		if p.get("topic_ids") is Array:
			for topic in p.topic_ids:
				if topic not in catalog.topics: errors.append("竞争话题未登记。")
		if p.get("skill_ids") is Array:
			for skill in p.skill_ids:
				if skill not in rules.skill_reach: errors.append("竞争能力未登记。")
		if not p.get("context_layer_attachment") is Dictionary or p.context_layer_attachment.size() != 5: errors.append("竞争脑切片绑定字段非法。")
		else:
			for layer in ["language","group","topics","stance","pragmatic"]:
				if not p.context_layer_attachment.get(layer) is bool: errors.append("竞争脑切片绑定必须为布尔值。")
		for key in ["political_position","pragmatic_position"]:
			if not p.get(key) is Array or p[key].size() != 2: errors.append("竞争坐标非法。")
			else:
				for value in p[key]:
					if not _number(value) or absf(float(value)) > 1.0: errors.append("竞争坐标非法。")
	for row: Dictionary in rules.countries:
		var c: Variant = data.countries.get(str(row.id))
		if not c is Dictionary: errors.append("竞争国家缺失。"); continue
		var valid := true
		for field in ["adopted","exposed","attention"]:
			if not c.get(field) is Dictionary or c[field].size() != ids.size(): valid = false; continue
			for id in c[field]:
				if not ids.has(id) or not _integer(c[field][id]) or int(c[field][id]) < 0: valid = false
		if not valid: errors.append("竞争分配类型或引用非法。"); continue
		if _sum(c.adopted) > int(row.population) or _sum(c.exposed) > int(row.population) or _sum(c.attention) > floori(int(row.population)*rules.attention_fraction): errors.append("竞争人口或注意力不守恒。")
		for id in c.adopted:
			if int(c.adopted[id]) > int(c.exposed[id]): errors.append("采用超过曝光。")
	if not errors.is_empty(): return errors
	if not data.victory.is_empty():
		var v: Dictionary = data.victory
		if not v.has_all(["id","eligible_ids","hour","owned_share","lineage_share","escaped_share","mutant_share","mutation_control_ratio","distinct_variants","equilibrium_hours","autonomous_hours"]) or not v.id is String or not v.eligible_ids is Array: return PackedStringArray(["胜利记录字段非法。"])
		for key in ["hour","distinct_variants","equilibrium_hours","autonomous_hours"]:
			if not _integer(v[key]) or int(v[key]) < 0: errors.append("胜利记录整数非法。")
		for key in ["owned_share","lineage_share","escaped_share","mutant_share","mutation_control_ratio"]:
			if not _number(v[key]) or float(v[key]) < 0.0 or float(v[key]) > 1.0: errors.append("胜利记录占比非法。")
		if not errors.is_empty(): return errors
		if int(v.hour) != hour or int(v.equilibrium_hours) != int(data.equilibrium_hours) or int(v.autonomous_hours) != int(data.autonomous_hours): errors.append("胜利记录时钟不一致。")
		var verifier: RefCounted = get_script().new(catalog)
		verifier._state = data.duplicate(true)
		var view: Dictionary = verifier.snapshot(variants,false)
		var actual: Dictionary = _eligibility(view,hour,int(data.autonomous_hours),int(data.equilibrium_hours))
		if v.eligible_ids.is_empty() or v.id != v.eligible_ids[0] or int(v.distinct_variants) != int(actual.distinct): errors.append("胜利条件与真实版本不一致。")
		var seen := {}
		for id: Variant in v.eligible_ids:
			if not id is String or id not in actual.ids or seen.has(id): errors.append("胜利条件未由真实传播达成。")
			seen[id] = true
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
