class_name MemeDemoCondition
extends Resource

const FIELDS := [&"hour", &"exposed", &"adopted", &"variants", &"families", &"fatigue"]
const OPERATORS := [&"ge", &"gt", &"le", &"lt", &"eq"]

@export var field: StringName = &"hour"
@export var operator: StringName = &"ge"
@export var value: float = 0.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not field in FIELDS:
		errors.append("Unknown condition field: %s" % field)
	if not operator in OPERATORS:
		errors.append("Unknown condition operator: %s" % operator)
	if not is_finite(value) or value < 0.0:
		errors.append("value: must be finite and nonnegative")
	elif field == &"fatigue" and value > 1.0:
		errors.append("value: fatigue threshold must be in [0, 1]")
	return errors
