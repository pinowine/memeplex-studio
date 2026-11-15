extends CanvasLayer

var _shape := -1
var _previous_mouse_mode: Input.MouseMode
var _previous_cursor_shape: Input.CursorShape

func install() -> void:
	name = "GameCursor"
	_previous_mouse_mode = Input.mouse_mode
	_previous_cursor_shape = Input.get_current_cursor_shape()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	apply(Input.CURSOR_ARROW)

func apply(shape: int) -> void:
	_shape = shape
	Input.set_default_cursor_shape(shape as Input.CursorShape)

func _exit_tree() -> void:
	Input.set_default_cursor_shape(_previous_cursor_shape)
	Input.mouse_mode = _previous_mouse_mode
