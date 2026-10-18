class_name AtlasMapSettings
extends Resource

@export var world_size := Vector2(1000, 650)
@export var ocean_margin: float = 65.0
@export var minimum_groups: int = 3
@export var maximum_groups: int = 4
@export var area_exponent: float = 0.45
@export var area_jitter: float = 0.04
@export var coast_samples: int = 1536
@export var curve_sample_distance: float = 0.6
@export var countries: Array[MapCountryDefinition]
@export var country_colors: PackedColorArray
@export var border_color: Color
@export var coast_color: Color
@export var border_width: float = 0.24
@export var selected_border_color: Color
@export var selected_border_width: float = 1.2
@export var selected_border_zoom_exponent: float = 0.5
@export var coast_width: float = 1.0
@export var hover_color: Color
@export var selection_color: Color
@export var river_color: Color
@export var relief_color: Color
@export var river_width: float = 1.5
@export var relief_width: float = 1.0
@export var capital_zoom: float = 1.8
@export var local_zoom: float = 3.4

@export var terrain_step: float = 4.0
@export var terrain_frequency: float = 0.014
@export var terrain_octaves: int = 5
@export var river_catchment: float = 12.0
@export var river_bend_reach: float = 0.30
@export var river_bend_slope_scale: float = 0.015
@export var river_valley_corridor: float = 1.2
@export var river_routing_grade: float = 0.00001
@export var river_basin_min_cost: float = 0.05
@export var river_basin_depth_scale: float = 0.04
@export var terrain_material: ShaderMaterial

@export var river_min_width: float = 0.12
@export var river_flow_scale: float = 0.065
@export var lake_color: Color
@export var water_max_opacity: float = 0.58
@export var water_fade_start: float = 1.15
@export var water_fade_end: float = 2.4
@export var lake_basin_depth: float = 0.008
@export var lake_retention_ratio: float = 0.12
@export var lake_moisture_exponent: float = 2.0
@export var lake_visible_depth: float = 0.003
@export var lake_mesh_subdivisions: int = 4


@export var macro_boundary_frequency: float = 0.004
@export var middle_boundary_frequency: float = 0.022
@export var detail_boundary_frequency: float = 0.14
@export var macro_boundary_strength: float = 52.0
@export var middle_boundary_strength: float = 24.0
@export var detail_boundary_strength: float = 3.2
@export var continental_middle_amplitude: float = 1.0
@export var continental_detail_amplitude: float = 1.0

@export var partition_macro_amplitude: float = 0.12
@export var partition_middle_amplitude: float = 0.15
@export var partition_detail_amplitude: float = 0.022

func latitude_at(point: Vector2) -> float:
	return 90.0 - 180.0 * point.y / world_size.y

func world_y_at_latitude(latitude: float) -> float:
	return world_size.y * (90.0 - latitude) / 180.0
