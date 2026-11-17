class_name MemeDemoEventClock
extends Resource

@export var daily_expectation: float = 0.4

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(daily_expectation) or daily_expectation < 0.0 or daily_expectation > 24.0:
		errors.append("daily_expectation must be finite and in [0, 24]")
	return errors

func arrival_hours(run_seed: int, day: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if day < 0 or not validate().is_empty() or daily_expectation == 0.0:
		return result
	# Bounded intervals preserve the mean without sending several sheets at once.
	var random := RandomNumberGenerator.new()
	random.seed = run_seed ^ 104729
	var interval := 24.0 / daily_expectation
	var hour := 0
	while hour < (day + 1) * 24:
		hour += maxi(1, roundi(random.randf_range(interval * 0.6, interval * 1.4)))
		if hour > day * 24 and hour <= (day + 1) * 24: result.append(hour)
	return result

func minimum_interval_hours() -> int:
	return maxi(1, roundi(24.0 / daily_expectation * 0.6)) if daily_expectation > 0.0 else 0
