class_name MemeDemoEventClock
extends Resource

@export var daily_expectation: float = 1.7

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not is_finite(daily_expectation) or daily_expectation < 0.0 or daily_expectation > 24.0:
		errors.append("daily_expectation must be finite and in [0, 24]")
	return errors

func arrival_hours(run_seed: int, day: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if day < 0 or not validate().is_empty() or daily_expectation == 0.0:
		return result
	# A geometric daily quota has variance mean * (1 + mean).
	var random := RandomNumberGenerator.new()
	random.seed = run_seed ^ ((day + 1) * 104729)
	var survival := daily_expectation / (1.0 + daily_expectation)
	var quota := floori(log(maxf(random.randf(), 0.000000000001)) / log(survival))
	for index in quota:
		result.append(day * 24 + random.randi_range(1, 24))
	result.sort()
	return result
