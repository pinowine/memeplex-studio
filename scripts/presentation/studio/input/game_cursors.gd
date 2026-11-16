extends CanvasLayer

const CURSORS := {
	Input.CURSOR_ARROW: {"texture": preload("res://assets/image/ui/cursors/arrow.svg"), "hotspot": Vector2(4, 3)},
	Input.CURSOR_HELP: {"texture": preload("res://assets/image/ui/cursors/info.svg"), "hotspot": Vector2(16, 16)},
	Input.CURSOR_POINTING_HAND: {"texture": preload("res://assets/image/ui/cursors/hand.svg"), "hotspot": Vector2(15, 3)},
	Input.CURSOR_CROSS: {"texture": preload("res://assets/image/ui/cursors/inspect.svg"), "hotspot": Vector2(14, 14)},
	Input.CURSOR_FORBIDDEN: {"texture": preload("res://assets/image/ui/cursors/forbidden.svg"), "hotspot": Vector2(16, 16)},
}

var _previous_mouse_mode: Input.MouseMode
var _previous_cursor_shape: Input.CursorShape

func install() -> void:
	name = "GameCursor"
	_previous_mouse_mode = Input.mouse_mode
	_previous_cursor_shape = Input.get_current_cursor_shape()
	for shape: int in CURSORS:
		Input.set_custom_mouse_cursor(CURSORS[shape].texture, shape, CURSORS[shape].hotspot)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	apply(Input.CURSOR_ARROW)

func apply(shape: int) -> void:
	Input.set_default_cursor_shape(shape as Input.CursorShape)

func _exit_tree() -> void:
	for shape: int in CURSORS:
		Input.set_custom_mouse_cursor(null, shape)
	Input.set_default_cursor_shape(_previous_cursor_shape)
	Input.mouse_mode = _previous_mouse_mode
