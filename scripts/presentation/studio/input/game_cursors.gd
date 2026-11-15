extends CanvasLayer

const ARROW := preload("res://assets/image/ui/cursors/arrow.svg")
const INFO := preload("res://assets/image/ui/cursors/info.svg")
const HAND := preload("res://assets/image/ui/cursors/hand.svg")
const INSPECT := preload("res://assets/image/ui/cursors/inspect.svg")
const FORBIDDEN := preload("res://assets/image/ui/cursors/forbidden.svg")

var _image := TextureRect.new()
var _shape := -1
var _previous_mouse_mode: Input.MouseMode

func install() -> void:
	name = "GameCursor"
	layer = 1025
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous_mouse_mode = Input.mouse_mode
	_image.name = "Pointer"
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_image)
	# Only this layer draws the pointer; Control and SubViewport cursors stay hidden.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	apply(Input.CURSOR_ARROW)

static func texture_for(shape: int) -> Texture2D:
	match shape:
		Input.CURSOR_HELP: return INFO
		Input.CURSOR_POINTING_HAND: return HAND
		Input.CURSOR_CROSS: return INSPECT
		Input.CURSOR_FORBIDDEN: return FORBIDDEN
	return ARROW

static func hotspot_for(shape: int) -> Vector2:
	match shape:
		Input.CURSOR_HELP: return Vector2(16, 16)
		Input.CURSOR_POINTING_HAND: return Vector2(15, 3)
		Input.CURSOR_CROSS: return Vector2(14, 14)
		Input.CURSOR_FORBIDDEN: return Vector2(16, 16)
	return Vector2(4, 3)

func apply(shape: int) -> void:
	if shape != _shape:
		_shape = shape
		_image.texture = texture_for(shape)
		_image.size = _image.texture.get_size()
	_update_position(get_viewport().get_mouse_position())

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_update_position(event.position)

func _process(_delta: float) -> void:
	_update_position(get_viewport().get_mouse_position())

func _update_position(point: Vector2) -> void:
	_image.position = point - hotspot_for(_shape)
	_image.visible = get_window().has_focus() and get_viewport().get_visible_rect().has_point(point)

func _exit_tree() -> void:
	Input.mouse_mode = _previous_mouse_mode
