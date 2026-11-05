extends RefCounted

const ARROW := preload("res://assets/image/ui/cursors/arrow.svg")
const HAND := preload("res://assets/image/ui/cursors/hand.svg")
const INSPECT := preload("res://assets/image/ui/cursors/inspect.svg")

static func install() -> void:
	Input.set_custom_mouse_cursor(ARROW, Input.CURSOR_ARROW, Vector2(4, 3))
	Input.set_custom_mouse_cursor(HAND, Input.CURSOR_POINTING_HAND, Vector2(15, 3))
	Input.set_custom_mouse_cursor(INSPECT, Input.CURSOR_HELP, Vector2(14, 14))

static func apply(shape: int) -> void:
	Input.set_default_cursor_shape(shape as Input.CursorShape)
	# Forwarded SubViewport input does not update the window cursor.
	DisplayServer.cursor_set_shape(shape as DisplayServer.CursorShape)
