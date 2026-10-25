class_name MapCountryDefinition
extends Resource

@export var id: StringName
@export var short_name_key: StringName
@export var official_name_key: StringName
@export var prototype_key: StringName
@export var description_key: StringName
@export var population: int
@export var topics_key: StringName
@export var events_key: StringName
@export var competitors_key: StringName

@export var reference_area_km2: float
@export var reference_members: PackedStringArray
@export var site_name_keys: PackedStringArray
@export var geography_name_key: StringName
@export var population_configured: bool = true
