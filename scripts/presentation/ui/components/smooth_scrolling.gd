extends Node

const WHEEL_STEP := 72.0
const DURATION := 0.16
const MOTION_NODE := "SmoothScrollMotion"


class ScrollMotion extends Node:
	var bar: ScrollBar
	var target := 0.0
	var tween: Tween
	var writing := false

	func _init(scrollbar: ScrollBar) -> void:
		bar = scrollbar
		name = MOTION_NODE
		target = bar.value
		bar.value_changed.connect(_value_changed)
		bar.changed.connect(stop)
		bar.visibility_changed.connect(_visibility_changed)
		bar.gui_input.connect(_gui_input)

	func move_by(distance: float) -> bool:
		var start := target if tween != null else bar.value
		var destination := clampf(start + distance, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))
		if is_equal_approx(destination, start):
			return tween != null and not is_equal_approx(bar.value, target)
		stop()
		target = destination
		tween = bar.create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_method(_write_value, bar.value, target, DURATION)
		tween.finished.connect(_finished)
		return true

	func stop() -> void:
		if tween != null:
			tween.kill()
			tween = null
		target = bar.value

	func _write_value(value: float) -> void:
		writing = true
		bar.value = value
		writing = false

	func _value_changed(_value: float) -> void:
		if not writing: stop()

	func _visibility_changed() -> void:
		if not bar.is_visible_in_tree(): stop()

	func _finished() -> void:
		tween = null
		target = bar.value

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			var direction := wheel_direction(event)
			if direction != 0.0:
				if move_by(direction * WHEEL_STEP * event.factor): bar.accept_event()
			else:
				stop()
		elif event is InputEventPanGesture or event is InputEventScreenTouch or event is InputEventKey:
			stop()

	static func wheel_direction(event: InputEventMouseButton) -> float:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT: return -1.0
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT: return 1.0
		return 0.0


func _enter_tree() -> void:
	get_tree().node_added.connect(_node_added)


func _ready() -> void:
	_register_tree(get_tree().root)


func _register_tree(node: Node) -> void:
	_node_added(node)
	for child in node.get_children(true):
		_register_tree(child)


func _node_added(node: Node) -> void:
	if node is ScrollContainer or node is RichTextLabel or node is ItemList or node is TextEdit or node is ScrollBar:
		_register.call_deferred(weakref(node))


func _register(reference: WeakRef) -> void:
	var control := reference.get_ref() as Control
	if control == null or not control.is_inside_tree(): return
	if control is TextEdit:
		control.scroll_smooth = true
		return
	if control is ScrollBar:
		if not control.get_parent() is TextEdit: _motion(control)
		return
	var callback := _control_input.bind(control)
	if not control.gui_input.is_connected(callback): control.gui_input.connect(callback)


func _control_input(event: InputEvent, control: Control) -> void:
	if control is RichTextLabel and not control.scroll_active: return
	if event is InputEventMouseButton and not event.pressed:
		# RichTextLabel handles wheel releases as scroll input too.
		if control is RichTextLabel and ScrollMotion.wheel_direction(event) != 0.0: control.accept_event()
		return
	if event is InputEventMouseButton and event.pressed:
		var direction := ScrollMotion.wheel_direction(event)
		if direction != 0.0:
			var horizontal: bool = event.button_index == MOUSE_BUTTON_WHEEL_LEFT or event.button_index == MOUSE_BUTTON_WHEEL_RIGHT
			if control is ScrollContainer:
				var swap_axes: bool = control.scroll_horizontal_by_default != event.shift_pressed
				var vertical_enabled: bool = control.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
				var horizontal_enabled: bool = control.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
				var vertical_hidden: bool = not control.get_v_scroll_bar().is_visible() and control.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_SHOW_NEVER
				var horizontal_hidden: bool = not control.get_h_scroll_bar().is_visible() and control.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_SHOW_NEVER
				if horizontal:
					horizontal = not ((vertical_enabled and swap_axes) or horizontal_hidden)
				else:
					horizontal = (horizontal_enabled and swap_axes) or vertical_hidden
				var mode: int = control.horizontal_scroll_mode if horizontal else control.vertical_scroll_mode
				if mode == ScrollContainer.SCROLL_MODE_DISABLED: return
			elif control is ItemList and not horizontal:
				horizontal = event.shift_pressed
			var bar: ScrollBar
			if horizontal:
				if control is RichTextLabel: return
				bar = control.get_h_scroll_bar()
			else:
				bar = control.get_v_scroll_bar()
			if not control is ScrollContainer and not bar.is_visible_in_tree(): return
			var step := WHEEL_STEP
			if control is ScrollContainer:
				var custom_step: float = control.scroll_horizontal_custom_step if horizontal else control.scroll_vertical_custom_step
				if custom_step > 0.0: step = custom_step
			if scroll_by(bar, direction * step * event.factor): control.accept_event()
		else:
			_stop_control(control)
	elif event is InputEventPanGesture or event is InputEventScreenTouch or event is InputEventKey:
		_stop_control(control)


func _stop_control(control: Control) -> void:
	_motion(control.get_v_scroll_bar()).stop()
	if not control is RichTextLabel: _motion(control.get_h_scroll_bar()).stop()


static func _motion(bar: ScrollBar) -> ScrollMotion:
	var motion := bar.get_node_or_null(NodePath(MOTION_NODE)) as ScrollMotion
	if motion == null:
		motion = ScrollMotion.new(bar)
		bar.add_child(motion, false, Node.INTERNAL_MODE_BACK)
	return motion


static func scroll_by(bar: ScrollBar, distance: float) -> bool:
	return _motion(bar).move_by(distance)


static func cancel(bar: ScrollBar) -> void:
	_motion(bar).stop()
