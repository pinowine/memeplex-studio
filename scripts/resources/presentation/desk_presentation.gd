extends Resource
class_name DeskPresentation

@export var shadows_enabled := true
@export var shadow_offset := Vector2(9, 12)
@export_range(0, 40) var shadow_blur := 9.0
@export_range(0, 1) var shadow_opacity := 0.34
@export_range(0, 30) var ao_radius := 4.0
@export_range(0, 1) var ao_strength := 0.35
@export var shadow_color := Color(0.12, 0.10, 0.08, 1)
@export_range(0.1, 3) var event_feed_duration := 0.85
@export_range(5, 150) var log_chars_per_second := 48.0
@export_range(20, 500) var log_feed_speed := 150.0
@export_range(4, 40) var dot_pitch := 14.0
@export_range(0, 1) var ink_strength := 0.28
@export var ink_color := Color(0.16, 0.20, 0.17, 1)
@export_range(0, 1) var tint_mix := 0.08
@export_range(0, 12) var posterize_levels := 0.0
