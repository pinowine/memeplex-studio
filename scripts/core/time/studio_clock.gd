class_name PressStudioClock
extends RefCounted

const DAY_SECONDS: float = 86400.0
const WEATHER: PackedStringArray = ["☀️", "☁️", "🌧️", "❄️", "🌬️"]

var settings: PressStudioSettings
var studio_index: int = -1
var studio_latitude: float = 0.0
var seed_value: int = 0
var utc_seconds: float = 0.0
var speed: int = 0
var previous_speed: int = 1

func _init(configuration: PressStudioSettings) -> void:
	settings = configuration
	reset()

func reset() -> void:
	studio_index = -1
	studio_latitude = 0.0
	speed = 0
	previous_speed = 1
	utc_seconds = Time.get_unix_time_from_datetime_string(settings.start_date + "T00:00:00")

func establish(index: int, map_seed: int, latitude: float) -> void:
	studio_index = index
	studio_latitude = latitude
	seed_value = map_seed
	utc_seconds = Time.get_unix_time_from_datetime_string(settings.start_date + "T00:00:00") - settings.utc_offsets[index] * 3600.0
	speed = 0

func set_speed(value: int) -> void:
	# Selecting a location precedes starting the studio clock.
	if studio_index < 0:
		return
	speed = value
	if value > 0:
		previous_speed = value

func toggle_pause() -> void:
	set_speed(previous_speed if speed == 0 else 0)

func advance(delta: float) -> void:
	if speed == 0:
		return
	var duration := settings.normal_seconds_per_day if speed == 1 else settings.fast_seconds_per_day
	utc_seconds += delta * DAY_SECONDS / duration

func local_seconds() -> float:
	if studio_index < 0:
		return utc_seconds
	return utc_seconds + settings.utc_offsets[studio_index] * 3600.0

func local_date() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(floori(local_seconds()))

func day_phase() -> float:
	return fposmod(local_seconds(), DAY_SECONDS) / DAY_SECONDS

func year_phase() -> float:
	var date := local_date()
	var march := Time.get_unix_time_from_datetime_string("%04d-03-01T00:00:00" % date.year)
	if local_seconds() < march:
		march = Time.get_unix_time_from_datetime_string("%04d-03-01T00:00:00" % (date.year - 1))
	var start := Time.get_datetime_dict_from_unix_time(march)
	var following := Time.get_unix_time_from_datetime_string("%04d-03-01T00:00:00" % (start.year + 1))
	var phase := (local_seconds() - march) / float(following - march)
	if studio_index >= 0 and studio_latitude < 0.0:
		phase = fposmod(phase + 0.5, 1.0)
	return phase

func season_mix() -> Vector4:
	var season := year_phase() * 4.0
	var weights := Vector4.ZERO
	var current := floori(season) % 4
	# Seasonal ink changes blend through the calendar instead of switching on one frame.
	var transition := smoothstep(0.65, 1.0, fposmod(season, 1.0))
	weights[current] = 1.0 - transition
	weights[(current + 1) % 4] = transition
	return weights

func daylight_fraction() -> float:
	if studio_index < 0:
		return 0.5
	var date := local_date()
	var year_start := Time.get_unix_time_from_datetime_string("%04d-01-01T00:00:00" % date.year)
	var year_end := Time.get_unix_time_from_datetime_string("%04d-01-01T00:00:00" % (date.year + 1))
	var gamma := TAU * ((local_seconds() - year_start) / DAY_SECONDS - 0.5) / ((year_end - year_start) / DAY_SECONDS)
	# NOAA's solar approximation supplies a visual day length, not a weather forecast.
	var declination := 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma) - 0.006758 * cos(2.0 * gamma) + 0.000907 * sin(2.0 * gamma) - 0.002697 * cos(3.0 * gamma) + 0.00148 * sin(3.0 * gamma)
	var latitude := deg_to_rad(studio_latitude)
	var center := sin(latitude) * sin(declination)
	var amplitude := cos(latitude) * cos(declination)
	var horizon := cos(deg_to_rad(90.833))
	# Solar-height extrema identify polar day and night before the hour-angle division.
	if center - amplitude >= horizon:
		return 1.0
	if center + amplitude <= horizon:
		return 0.0
	return acos((horizon - center) / amplitude) / PI

func weather() -> String:
	if studio_index < 0:
		return "—"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s:%d" % [seed_value, settings.country_ids[studio_index], floori(local_seconds() / DAY_SECONDS)])
	var season := floori(year_phase() * 4.0) % 4
	var offset := (settings.weather_climates[studio_index] * 4 + season) * WEATHER.size()
	var total: int = 0
	for i in WEATHER.size():
		total += settings.weather_weights[offset + i]
	var choice := rng.randi_range(1, total)
	var index: int = 0
	while choice > settings.weather_weights[offset + index]:
		choice -= settings.weather_weights[offset + index]
		index += 1
	return WEATHER[index]

func inspection() -> Dictionary:
	return {"studio":studio_index, "studio_latitude":studio_latitude, "speed":speed, "previous_speed":previous_speed, "utc_seconds":utc_seconds, "local_date":local_date(), "day_phase":day_phase(), "year_phase":year_phase(), "daylight_fraction":daylight_fraction(), "weather":weather(), "season_mix":season_mix()}
