class_name MemeGameplayRules
extends Resource

@export var policy_version: int = 1
@export var horizon_hours: int = 1440
@export var hours_per_active_second: float = 1.2
@export var event_time_scale: float = 20.0
@export var attention_fraction: float = 0.025
@export var attention_activation: float = 4.0
@export var adoption_response: float = 0.006
@export var exposure_response: float = 0.006
@export var seed_pressure: float = 0.02
@export var seed_hours: int = 480
@export var parent_relay: float = 0.015
@export var expression_character_scale: float = 80.0
@export var expression_floor: float = 0.10
@export var autonomous_language_access: float = 0.8
@export var autonomous_recognizability: float = 0.8
@export var autonomous_context_dependency: float = 0.3
@export var occupancy_multiplier: float = 1.55
@export var occupancy_cap: float = 0.98
@export var travel_distance_scale: float = 1000.0
@export var land_contact: float = 0.0001
@export var sea_contact: float = 0.00001
@export var network_contact_multiplier: float = 100.0
@export var sea_neighbors: int = 2
@export var reference_geometry_seed: int = 20261003
@export var controlled_refresh_hours: float = 4000.0
@export var community_refresh_hours: float = 6000.0
@export var fatigue_gain: float = 0.0003
@export var fatigue_recovery: float = 0.0001
@export var fitness_weights: Dictionary = {"language":0.20,"group":0.15,"topics":0.20,"stance":0.10,"pragmatic":0.10,"expression":0.15,"access":0.10}
@export var skill_reach: Dictionary = {"text":0.0,"image":0.18,"translation":0.12,"remix":0.18,"network":0.45}
@export var ownership_victory_share: float = 0.60
@export var lineage_victory_share: float = 0.60
@export var distinct_variant_min_share: float = 0.01
@export var autonomous_min_share: float = 0.10
@export var autonomous_survival_hours: int = 24
@export var equilibrium_min_hours: int = 720
@export var equilibrium_window_hours: int = 720
@export var equilibrium_tolerance: float = 0.03
@export var equilibrium_variant_min_share: float = 0.01
@export var equilibrium_min_side_share: float = 0.01
@export var milestone_population_fraction: float = 0.01
@export var countries: Array[Dictionary] = []
@export var event_presets: Dictionary = {}
@export var map_settings: AtlasMapSettings
@export var evidence_status: StringName = &"game_policy"

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if policy_version != 1 or horizon_hours < equilibrium_min_hours or hours_per_active_second <= 0.0 or not is_finite(hours_per_active_second): errors.append("Invalid gameplay horizon or pace")
	for key in ["attention_fraction","adoption_response","exposure_response","seed_pressure","parent_relay","expression_floor","autonomous_language_access","autonomous_recognizability","autonomous_context_dependency","occupancy_cap","land_contact","sea_contact","ownership_victory_share","lineage_victory_share","distinct_variant_min_share","autonomous_min_share","equilibrium_tolerance","equilibrium_min_side_share","equilibrium_variant_min_share","milestone_population_fraction","fatigue_gain","fatigue_recovery"]:
		var value: float = float(get(key))
		if not is_finite(value) or value <= 0.0 or value > 1.0: errors.append("Invalid gameplay fraction: " + key)
	if seed_hours <= 0 or controlled_refresh_hours <= 0.0 or community_refresh_hours <= 0.0 or autonomous_survival_hours <= 0 or equilibrium_window_hours <= 0 or sea_neighbors < 0: errors.append("Invalid gameplay timing")
	for key in ["attention_activation","event_time_scale","controlled_refresh_hours","community_refresh_hours","expression_character_scale","occupancy_multiplier","travel_distance_scale","network_contact_multiplier"]:
		if not is_finite(float(get(key))) or float(get(key)) <= 0.0: errors.append("Invalid gameplay scale: " + key)
	if network_contact_multiplier < 1.0 or network_contact_multiplier > 1000.0: errors.append("Invalid network contact multiplier")
	for id in skill_reach:
		if id not in ["text","image","translation","remix","network"] or not _number(skill_reach[id]) or float(skill_reach[id]) < 0.0 or float(skill_reach[id]) > 1.0: errors.append("Invalid propagation skill reach")
	var total := 0.0
	for key in ["language","group","topics","stance","pragmatic","expression","access"]:
		var value: Variant = fitness_weights.get(key)
		if not _number(value) or float(value) <= 0.0: errors.append("Invalid fitness weight: " + key)
		else: total += float(value)
	if not is_equal_approx(total, 1.0): errors.append("Fitness weights must sum to one")
	var seen := {}
	for row in countries:
		if not row.has_all(["id","population","population_source","languages","groups","topics","stance","pragmatic"]) or not row.get("id") is String or str(row.id).is_empty() or not row.get("population_source") is String or not _number(row.get("population")) or float(row.population) != floorf(float(row.population)) or int(row.population) <= 0 or seen.has(row.get("id")):
			errors.append("Invalid country gameplay profile")
			continue
		seen[row.id] = true
		for field in ["languages","groups","topics"]:
			if not row.get(field) is Dictionary: errors.append("Invalid country correlation: " + field)
			else:
				for value in row[field].values():
					if not _number(value) or float(value) < 0.0 or float(value) > 1.0: errors.append("Invalid correlation value")
		for field in ["stance","pragmatic"]:
			if not row.get(field) is Array or row[field].size() != 2: errors.append("Invalid country axis preference")
			else:
				for value in row[field]:
					if not _number(value) or absf(float(value)) > 1.0: errors.append("Invalid country axis preference")
	if countries.is_empty() or map_settings == null or evidence_status != &"game_policy": errors.append("World policy must declare its source and geography")
	if map_settings != null:
		if countries.size() != map_settings.countries.size(): errors.append("World policy must cover every geography country")
		else:
			for index in countries.size():
				if str(countries[index].get("id","")) != str(map_settings.countries[index].id): errors.append("World policy country order differs from geography")
	return errors

func signature() -> String:
	var data := {}
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE and property.name != "map_settings": data[property.name] = get(property.name)
	return JSON.stringify(data,"",true,true).sha256_text()

func country(id: String) -> Dictionary:
	for row in countries:
		if str(row.id) == id: return row
	return {}

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
