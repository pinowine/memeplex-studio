extends Resource
class_name DeskPresentation

@export_range(5, 600) var log_chars_per_second := 240.0
@export_range(20, 1200) var log_feed_speed := 600.0
@export_range(4, 40) var dot_pitch := 14.0
@export_range(0, 1) var ink_strength := 0.28
@export var ink_color := Color(0.16, 0.20, 0.17, 1)
@export_range(0, 1) var tint_mix := 0.08
@export_range(0, 12) var posterize_levels := 0.0
