extends RefCounted

const ACTION_IDS := ["pause", "slower", "faster", "speed_paused", "speed_normal", "speed_fast"]
const LABELS := {
	"pause":"LOC_KEY_PAUSE",
	"slower":"LOC_KEY_SLOWER",
	"faster":"LOC_KEY_FASTER",
	"speed_paused":"LOC_KEY_SPEED_PAUSED",
	"speed_normal":"LOC_KEY_SPEED_NORMAL",
	"speed_fast":"LOC_KEY_SPEED_FAST"
}
const DEFAULTS := {
	"pause":KEY_SPACE,
	"slower":KEY_COMMA,
	"faster":KEY_PERIOD,
	"speed_paused":KEY_F1,
	"speed_normal":KEY_F2,
	"speed_fast":KEY_F3
}

static var _bindings: Dictionary = DEFAULTS.duplicate()

static func defaults() -> Dictionary:
	return DEFAULTS.duplicate()

static func bindings() -> Dictionary:
	return _bindings.duplicate()

static func apply(values: Dictionary) -> void:
	_bindings = defaults()
	for action: String in ACTION_IDS:
		if values.has(action): _bindings[action] = int(values[action])

static func reset() -> void:
	_bindings = defaults()

static func assign(action: String, event: InputEventKey) -> Error:
	var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == 0 or key in [KEY_ESCAPE, KEY_F8, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]: return ERR_INVALID_PARAMETER
	var code := _event_code(event)
	if key == KEY_D and event.ctrl_pressed: return ERR_INVALID_PARAMETER
	for other: String in ACTION_IDS:
		if other != action and int(_bindings[other]) == code:
			_bindings[other] = _bindings[action]
			break
	_bindings[action] = code
	return OK

static func matches(event: InputEventKey, action: String) -> bool:
	return _event_code(event) == int(_bindings[action])

static func display_name(action: String) -> String:
	return OS.get_keycode_string(_bindings[action])

static func _event_code(event: InputEventKey) -> int:
	return event.get_physical_keycode_with_modifiers() if event.physical_keycode != 0 else event.get_keycode_with_modifiers()
