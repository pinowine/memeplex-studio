@tool
extends ScrollContainer

signal preview_requested(index: int)
signal hovered(index: int)

const ContextCard = preload("res://scripts/presentation/studio/paper/starter_context_card.gd")
const ReceiptStyle = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const BODY_FONT = preload("res://assets/image/fonts/development_font.tres")
const GAP := 12.0
const PADDING := 16.0

var _options: Array = []
var _selected := -1
var _grid: GridContainer
var _buttons: Array[Button] = []
var _cards: Array[Control] = []
var _marks: Array[Label] = []

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	add_child(_grid)
	resized.connect(_layout_cards)
	mouse_exited.connect(func(): hovered.emit(-1))

func set_options(options: Array, selected: int) -> void:
	var records := options.duplicate(true)
	for record: Dictionary in records: record.erase("selected")
	if _options == records:
		_select(selected)
		return
	_options = records
	for button: Button in _buttons:
		_grid.remove_child(button)
		button.queue_free()
	_buttons.clear()
	_cards.clear()
	_marks.clear()
	for index in _options.size():
		var button := Button.new()
		button.name = "Starter%d" % index
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(button)
		var card := ContextCard.new()
		card.configure(_options[index], BODY_FONT, false)
		button.add_child(card)
		card.minimum_size_changed.connect(_layout_cards.call_deferred)
		var mark := Label.new()
		mark.text = "✓"
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.add_theme_color_override("font_color", ReceiptStyle.SECTION_TEAL)
		button.add_child(mark)
		button.pressed.connect(func(): preview_requested.emit(index))
		button.mouse_entered.connect(func(): hovered.emit(index))
		button.focus_entered.connect(func(): hovered.emit(index))
		_buttons.append(button)
		_cards.append(card)
		_marks.append(mark)
	_select(selected)
	_layout_cards()

func _select(index: int) -> void:
	_selected = index
	for row in _buttons.size():
		var selected := row == index
		_buttons[row].set_pressed_no_signal(selected)
		_marks[row].visible = selected
		var paper := StyleBoxFlat.new()
		paper.bg_color = Color(ReceiptStyle.SECTION_TEAL, .12) if selected else Color.TRANSPARENT
		paper.border_color = ReceiptStyle.SECTION_TEAL if selected else ReceiptStyle.EDGE
		paper.set_border_width_all(2 if selected else 1)
		_buttons[row].add_theme_stylebox_override("normal", paper)
		_buttons[row].add_theme_stylebox_override("pressed", paper)

func set_enabled(enabled: bool) -> void:
	for index in _buttons.size():
		_buttons[index].disabled = not enabled or bool(_options[index].get("disabled", false))

func fit_width(width: float) -> float:
	size.x = width
	_layout_cards()
	return _grid.get_combined_minimum_size().y

func _layout_cards() -> void:
	_grid.columns = 3 if size.x >= 660 else 1
	var width := (size.x - GAP * (_grid.columns - 1)) / _grid.columns
	for index in _cards.size():
		var card := _cards[index]
		card.position = Vector2.ONE * PADDING
		card.fit_width(width - PADDING * 2.0)
		_buttons[index].custom_minimum_size.y = card.get_combined_minimum_size().y + PADDING * 2.0
		_marks[index].position = Vector2(width - 26, _buttons[index].custom_minimum_size.y - 28)

func handles_viewport_point(point: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().has_point(point)

func inspection() -> Dictionary:
	var rows: Array[Dictionary] = []
	for index in _buttons.size():
		rows.append({"id":_options[index].id, "rect":_buttons[index].get_global_rect(), "selected":index == _selected})
	return {"selected":_selected, "columns":_grid.columns, "options":rows, "rect":get_global_rect()}
