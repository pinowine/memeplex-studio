class_name PressStudioSettings
extends Resource

@export var start_date: String = "2000-01-01"
@export var normal_seconds_per_day: float = 5.0
@export var fast_seconds_per_day: float = 2.0
@export var restart_hold_seconds: float = 1.5
@export var country_ids: PackedStringArray
@export var latitudes: PackedFloat32Array
@export var utc_offsets: PackedFloat32Array
@export var weather_climates: PackedInt32Array
@export var weather_weights: PackedInt32Array
