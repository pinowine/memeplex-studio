extends ScrollContainer

signal anchor_changed(anchor: Dictionary)

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
var _column: VBoxContainer
var _records: Array = []
var _rows: Array[Control] = []
var _anchor := {}
var _syncing := false

func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	vertical_scroll_mode = SCROLL_MODE_AUTO
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 14)
	add_child(_column)
	_column.sort_children.connect(_restore_anchor.call_deferred)
	get_v_scroll_bar().scrolling.connect(func(): _scroll_changed(get_v_scroll_bar().value))

func configure(records: Array, anchor: Dictionary) -> void:
	_syncing = true
	_anchor = anchor.duplicate()
	if _records != records:
		_records = records.duplicate(true)
		for row: Control in _rows:
			_column.remove_child(row)
			row.queue_free()
		_rows.clear()
		for record: Dictionary in records:
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			_column.add_child(row)
			var label := RichTextLabel.new()
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			label.fit_content = true
			label.scroll_active = false
			label.selection_enabled = true
			label.mouse_filter = Control.MOUSE_FILTER_PASS
			label.add_theme_font_override("normal_font", Style.FONT)
			label.add_theme_font_size_override("normal_font_size", 16)
			label.add_theme_constant_override("line_separation", 4)
			label.add_theme_color_override("default_color", Style.INK)
			label.text = str(record.body)
			row.add_child(label)
			var rule := HSeparator.new()
			rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(rule)
			_rows.append(row)
	_restore_anchor.call_deferred()

func _restore_anchor() -> void:
	_syncing = true
	var offset := 0.0
	for index in _records.size():
		if str(_records[index].id) == str(_anchor.get("id", "")):
			offset = _rows[index].position.y + _rows[index].size.y * float(_anchor.get("fraction", 0.0))
			break
	scroll_vertical = roundi(offset)
	_syncing = false

func _scroll_changed(value: float) -> void:
	if _syncing or _records.is_empty(): return
	for index in range(_rows.size() - 1, -1, -1):
		var row := _rows[index]
		if value < row.position.y and index > 0: continue
		_anchor = {"id":str(_records[index].id), "fraction":clampf((value - row.position.y) / maxf(1.0, row.size.y), 0.0, 1.0)}
		anchor_changed.emit(_anchor)
		return

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll_vertical += roundi(48.0 * event.factor) * (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		_scroll_changed(get_v_scroll_bar().value)
		accept_event()
