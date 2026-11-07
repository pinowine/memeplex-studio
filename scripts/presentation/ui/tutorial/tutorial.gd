class_name DeskTutorial
extends Control

signal step_changed(id: String, step: Dictionary)
signal finished(skipped: bool)
signal focus_changed(active: bool)
signal pointer_cancelled
signal drag_cancelled
signal overview_requested

const TEMPLATE = preload("res://scenes/ui/tutorial/tutorial.tscn")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const Arrow = preload("res://scripts/presentation/ui/tutorial/tutorial_arrow.gd")
const DragArrow = preload("res://scripts/presentation/ui/tutorial/tutorial_drag_arrow.gd")
const CARD_MARGIN := 20.0
const TARGET_GAP := 52.0
const MAX_ARROW_LENGTH := 72.0
const TYPE_SPEED := 32.0

class TypewriterEffect extends RichTextEffect:
	var bbcode := "typewriter"
	var progress := 0.0

	func _process_custom_fx(character: CharFXTransform) -> bool:
		character.color.a *= smoothstep(0.0, 3.0, progress - character.relative_index)
		return true

var _steps: Array[Dictionary] = []
var _index := 0
var _active := false
var _completed := false
var _blocked := false
var _hint_only := false
var _provider := Callable()
var _avoid_provider := Callable()
var _overview_provider := Callable()
var _drag_provider := Callable()
var _input_provider := Callable()
var _input_point_test := Callable()
var _pointer_mode := ""
var _press_point := Vector2.ZERO
var _press_rect := Rect2()
var _return_overview := false
var _avoid_rects: Array[Rect2] = []
var _target := Rect2()
var _drag_source := Rect2()
var _drag_source_point := Vector2.ZERO
var _drag_source_test := Callable()
var _ui: Control
var _history: Array[Dictionary] = []
var _display_index := 0
var _transition: Tween
var _transitioning := false
var _appearance := 0.0
var _card_position := Vector2.ZERO
var _arrow_from := Vector2.ZERO
var _arrow_to := Vector2.ZERO
var _arrow_visible := false
var _arrow: Node2D
var _drag_arrow: Node2D
var _typewriter := TypewriterEffect.new()
var _body_text := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Read the card projection after the studio updates its camera and paper meshes.
	process_priority = 101
	if theme == null: theme = load("res://data/presentation/ui/demo_theme.tres")
	_ui = TEMPLATE.instantiate()
	add_child(_ui)
	_ui.get_node("Card/Content/Body").install_effect(_typewriter)
	_arrow = Arrow.new()
	_arrow.name = "GuideArrow"
	add_child(_arrow)
	_arrow.hide()
	_drag_arrow = DragArrow.new()
	_drag_arrow.name = "DragGuideArrow"
	add_child(_drag_arrow)
	move_child(_drag_arrow, 0)
	_drag_arrow.hide()
	_ui.get_node("Card/Content/Actions/Continue").pressed.connect(advance)
	_ui.get_node("Card/Content/Actions/Skip").pressed.connect(skip)
	PaperStyle.apply_buttons(_ui)
	if _steps.is_empty(): _steps = default_steps()
	resized.connect(_refresh)
	resized.connect(_cancel_pointer)
	get_window().focus_exited.connect(_cancel_pointer)
	hide()

func configure(steps: Array[Dictionary] = [], target_provider: Callable = Callable(), avoid_provider: Callable = Callable(), overview_provider: Callable = Callable()) -> void:
	_steps = default_steps() if steps.is_empty() else steps.duplicate(true)
	_provider = target_provider
	_avoid_provider = avoid_provider
	_overview_provider = overview_provider
	_index = clampi(_index, 0, _steps.size() - 1)
	_refresh()

func set_target_provider(provider: Callable) -> void:
	_provider = provider
	_refresh()

func set_drag_target_provider(provider: Callable) -> void:
	_drag_provider = provider
	_refresh()

func set_input_target_provider(provider: Callable, point_test := Callable()) -> void:
	_input_provider = provider
	_input_point_test = point_test

func _input(event: InputEvent) -> void:
	if not allows_input(event): get_viewport().set_input_as_handled()

func allows_hover(viewport_point: Vector2) -> bool:
	if not _active or _hint_only: return true
	if _blocked or _transitioning or _return_overview: return false
	var point := get_global_transform_with_canvas().affine_inverse() * viewport_point
	if _drag_source.has_area() and _drag_source.has_point(point):
		return not _drag_source_test.is_valid() or _drag_source_test.call(viewport_point)
	return _contains_input_point(_input_areas(), point) and (not _input_point_test.is_valid() or _input_point_test.call(_steps[_index], viewport_point))

func allows_input(event: InputEvent) -> bool:
	if not _active or _hint_only: return true
	if _pointer_mode == "guide" and event is InputEventMouse:
		if event is InputEventMouseMotion: return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if not event.pressed: _pointer_mode = ""
			return true
	if event is InputEventMouse and handles_viewport_point(event.position) and _pointer_mode.is_empty():
		if event is InputEventMouseMotion: return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _pointer_mode = "guide"
			return true
	if _blocked or _transitioning: return false
	if event is InputEventKey:
		var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_ESCAPE and str(_steps[_index].get("target", "")).begins_with("map/"):
			if event.pressed and not event.echo: overview_requested.emit()
			return false
		if _return_overview and key == KEY_ESCAPE:
			if event.pressed and not event.echo: overview_requested.emit()
			return false
		if _return_overview: return false
		return str(_steps[_index].get("action", "")) == "speed_changed" and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and key in [KEY_SPACE, KEY_COMMA, KEY_LESS, KEY_PERIOD, KEY_GREATER]
	if not event is InputEventMouse: return false
	var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
	var areas := _input_areas()
	if event is InputEventMouseMotion:
		if not _pointer_mode.is_empty(): return true
		return _contains_input_point(areas, point) or _drag_source.has_point(point)
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return not _return_overview and str(_steps[_index].get("target", "")).begins_with("map/") and _contains_input_point(areas, point)
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return false
	if event.pressed:
		if _return_overview:
			return false
		_press_point = point
		if _drag_source.has_area() and _drag_source.has_point(point) and (not _drag_source_test.is_valid() or _drag_source_test.call(event.position)):
			_pointer_mode = "drag"
			return true
		for area: Rect2 in areas:
			if area.has_point(point):
				if _input_point_test.is_valid() and not _input_point_test.call(_steps[_index], event.position): return false
				_pointer_mode = "click"
				_press_rect = area
				return true
		return false
	if _pointer_mode.is_empty(): return false
	var allowed: bool = _target.has_point(point) and point.distance_to(_press_point) >= 8.0 if _pointer_mode == "drag" else _press_rect.has_point(point)
	if not allowed and _pointer_mode == "drag": drag_cancelled.emit()
	_pointer_mode = ""
	# A short click on a drag source must not open its details and leave the lesson.
	if not allowed: pointer_cancelled.emit()
	return allowed

func _input_areas() -> Array[Rect2]:
	var areas: Array[Rect2] = []
	if str(_steps[_index].get("action", "continue")) in ["continue", "module_installed", "context_installed"]: return areas
	if _input_provider.is_valid():
		var inverse := get_global_transform_with_canvas().affine_inverse()
		for area: Rect2 in _input_provider.call(_steps[_index]):
			if area.has_area(): areas.append(inverse * area)
	elif _target.has_area(): areas.append(_target)
	return areas

func _contains_input_point(areas: Array[Rect2], point: Vector2) -> bool:
	for area: Rect2 in areas:
		if area.has_point(point): return true
	return false

func _cancel_pointer() -> void:
	if _pointer_mode == "drag": drag_cancelled.emit()
	_pointer_mode = ""
	pointer_cancelled.emit()

func begin() -> void:
	_index = 0
	_history.clear()
	_completed = false
	_hint_only = false
	_open()

func set_step(id: String) -> bool:
	for index in _steps.size():
		if str(_steps[index].get("id", "")) == id:
			_index = index
			_hint_only = false
			_open()
			return true
	return false

func observe_action(id: String, payload: Dictionary = {}) -> bool:
	if not _active or _blocked or _hint_only: return false
	var step := _steps[_index]
	if str(step.get("action", "continue")) != id: return false
	for key: Variant in step.get("match", {}):
		if payload.get(key) != step.match[key]: return false
	_history.append({"step": str(step.id), "action": id, "payload": payload.duplicate(true)})
	_advance()
	return true

func advance() -> void:
	if not _active or _blocked or _transitioning: return
	if _typewriter.progress < _body_text.length() + 3.0:
		_typewriter.progress = _body_text.length() + 3.0
		return
	if _hint_only:
		_close(false)
		return
	observe_action("continue")

func skip() -> void:
	if not _active: return
	_close(true)

func reenter_hint() -> void:
	_hint_only = _completed
	_open()

func set_interaction_blocked(blocked: bool) -> void:
	if _blocked == blocked: return
	_blocked = blocked
	if blocked: _cancel_pointer()
	_refresh()

func _open() -> void:
	_cancel_pointer()
	_active = true
	show()
	_present_step()
	focus_changed.emit(true)
	step_changed.emit(str(_steps[_index].id), _steps[_index].duplicate(true))

func _advance() -> void:
	_cancel_pointer()
	if _index == _steps.size() - 1:
		_completed = true
		_close(false)
		return
	_index += 1
	_present_step()
	step_changed.emit(str(_steps[_index].id), _steps[_index].duplicate(true))

func _close(skipped: bool) -> void:
	_cancel_pointer()
	_active = false
	_stop_transition()
	_transitioning = true
	_transition = create_tween()
	_transition.tween_method(_set_appearance, _appearance, 0.0, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition.tween_callback(func():
		_transitioning = false
		hide())
	focus_changed.emit(false)
	finished.emit(skipped)

func _stop_transition() -> void:
	if _transition != null and _transition.is_valid(): _transition.kill()

func _present_step() -> void:
	_stop_transition()
	var previous_index := _display_index
	var previous_position := _card_position
	var previous_progress := _typewriter.progress
	_display_index = _index
	_refresh()
	# A card that stays in place only needs new ink.
	if _appearance >= 0.99 and previous_position.distance_to(_card_position) < 2.0:
		_transitioning = false
		_typewriter.progress = 0.0
		_refresh()
		return
	_display_index = previous_index
	_card_position = previous_position
	_refresh()
	_typewriter.progress = previous_progress
	_transitioning = true
	_transition = create_tween()
	if _appearance > 0.01:
		_transition.tween_method(_set_appearance, _appearance, 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition.tween_callback(func():
		_display_index = _index
		_typewriter.progress = 0.0
		_set_appearance(0.0))
	_transition.tween_method(_set_appearance, 0.0, 1.0, 0.30).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_callback(func():
		_transitioning = false
		_refresh())

func _set_appearance(value: float) -> void:
	_appearance = value
	_refresh()

func _process(delta: float) -> void:
	if not visible: return
	_refresh()
	if _active and not _transitioning:
		var speed := TYPE_SPEED * (1.8 if TranslationServer.get_locale().begins_with("en") else 1.0)
		_typewriter.progress = minf(_typewriter.progress + delta * speed, _body_text.length() + 3.0)

func _refresh() -> void:
	if not is_instance_valid(_ui) or _steps.is_empty(): return
	_display_index = clampi(_display_index, 0, _steps.size() - 1)
	var step := _steps[_display_index]
	_return_overview = _overview_provider.is_valid() and bool(_overview_provider.call(str(step.get("target", ""))))
	_ui.get_node("Card/Content/Title").text = DeskLocalization.text(str(step.get("title", "")))
	var text := DeskLocalization.text(str(step.get("text", "")))
	var body: RichTextLabel = _ui.get_node("Card/Content/Body")
	if text != _body_text:
		_body_text = text
		_typewriter.progress = 0.0
		body.clear()
		body.push_customfx(_typewriter, {})
		body.add_text(text)
		body.pop()
	var next: Button = _ui.get_node("Card/Content/Actions/Continue")
	next.text = (DeskLocalization.text("LOC_HIDE_HINT_FC06733C")) if _hint_only else (DeskLocalization.text("LOC_CONTINUE_7C969119"))
	var requires_action := not _hint_only and str(step.get("action", "continue")) != "continue"
	next.disabled = not _active or _blocked or _transitioning or requires_action
	_ui.get_node("Card/Content/Actions/Skip").text = DeskLocalization.text("LOC_SKIP_EXPLANATION_2786614D")
	_ui.get_node("Card/Content/Actions/Skip").disabled = not _active or _blocked
	_target = Rect2()
	if _provider.is_valid() and not str(step.get("target", "")).is_empty():
		var target: Variant = _provider.call(str(step.target))
		if target is Control and target.is_visible_in_tree():
			var transform: Transform2D = get_global_transform_with_canvas().affine_inverse() * target.get_global_transform_with_canvas()
			_target = transform * Rect2(Vector2.ZERO, target.size)
		elif target is Rect2: _target = get_global_transform_with_canvas().affine_inverse() * target
	_drag_source = Rect2()
	_drag_source_test = Callable()
	if _drag_provider.is_valid() and _display_index == _index:
		var drag_targets: Dictionary = _drag_provider.call(str(step.id))
		if not drag_targets.is_empty():
			var inverse := get_global_transform_with_canvas().affine_inverse()
			_drag_source = inverse * drag_targets.source
			_drag_source_point = inverse * drag_targets.source_point
			_drag_source_test = drag_targets.get("accepts_point", Callable())
			_target = inverse * drag_targets.target
	# Offscreen or missing targets never receive a speculative pointer.
	_target = _target.intersection(Rect2(Vector2.ZERO, size))
	if _drag_source.has_area():
		_drag_arrow.connect_points(_drag_source_point, _target.get_center())
	_avoid_rects.clear()
	if _avoid_provider.is_valid():
		var reserved: Variant = _avoid_provider.call()
		if reserved is Array:
			var inverse := get_global_transform_with_canvas().affine_inverse()
			for rectangle: Variant in reserved:
				if rectangle is Rect2 and rectangle.has_area():
					_avoid_rects.append(inverse * rectangle)
	if _drag_source.has_area(): _avoid_rects.append(_drag_source)
	var card: Control = _ui.get_node("Card")
	var compact := size.x < 900 or size.y < 560
	var width := minf(600 if compact else 500, size.x - CARD_MARGIN * 2.0)
	var minimum_width := 268.0 if compact else 344.0
	# The live phone paper reserves the right side, including while it slides in.
	for rectangle: Rect2 in _avoid_rects:
		if rectangle.get_center().x > size.x * .5:
			width = minf(width, maxf(minimum_width, rectangle.position.x - CARD_MARGIN * 2.0 - TARGET_GAP))
	card.get_node("Portrait67").visible = not compact
	card.get_node("Speaker").visible = not compact
	var title: Label = card.get_node("Content/Title")
	var title_size := 18 if compact else 21
	var body_size := 14 if compact else 17
	if title.get_theme_font_size("font_size") != title_size: title.add_theme_font_size_override("font_size", title_size)
	if body.get_theme_font_size("normal_font_size") != body_size: body.add_theme_font_size_override("normal_font_size", body_size)
	var waiting: Label = _ui.get_node("Card/Content/Waiting")
	waiting.visible = not _blocked and (_return_overview or (requires_action and not compact))
	if _return_overview:
		waiting.text = DeskLocalization.text("LOC_PRESS_ESC_TO_RETURN_TO_THE_MAIN_445EA13C")
	else:
		waiting.text = DeskLocalization.text("LOC_FOLLOW_THE_CURRENT_PROMPT_TO_FINISH_THE_40A63035")
	var minimum_height := 128.0 if compact else 190.0
	card.size = Vector2(width, minimum_height)
	var content: Control = card.get_node("Content")
	content.position = Vector2(14, 14) if compact else Vector2(94, 18)
	var separation := 6 if compact else 8
	if content.get_theme_constant("separation") != separation: content.add_theme_constant_override("separation", separation)
	var padding := Vector2(28, 28) if compact else Vector2(112, 36)
	content.size = card.size - padding
	body.size.x = content.size.x
	waiting.size.x = content.size.x
	card.size.y = maxf(minimum_height, content.get_combined_minimum_size().y + padding.y)
	content.size = card.size - padding
	_card_position = _place_card(card.size)
	card.pivot_offset = Vector2(0, card.size.y * 0.5)
	card.scale = Vector2(lerpf(0.04, 1.0, _appearance), lerpf(0.82, 1.0, _appearance))
	card.position = _card_position
	_ui.modulate.a = smoothstep(0.0, 0.25, _appearance)
	# The pointer follows the settled card edges while the paper unfolds.
	_update_arrow(Rect2(_card_position, card.size))
	queue_redraw()

func _place_card(dimensions: Vector2) -> Vector2:
	var candidates: Array[Vector2] = []
	if _target.has_area():
		# Three alignments per edge keep the bubble close even near a screen corner.
		for alignment: float in [0.5, 0.0, 1.0]:
			var x := lerpf(_target.position.x, _target.end.x, alignment) - dimensions.x * alignment
			var y := lerpf(_target.position.y, _target.end.y, alignment) - dimensions.y * alignment
			candidates.append(Vector2(_target.end.x + TARGET_GAP, y))
			candidates.append(Vector2(_target.position.x - dimensions.x - TARGET_GAP, y))
			candidates.append(Vector2(x, _target.position.y - dimensions.y - TARGET_GAP))
			candidates.append(Vector2(x, _target.end.y + TARGET_GAP))
	else:
		# General dialogue has a quiet resting position and no implied target.
		candidates.append(Vector2((size.x - dimensions.x) * 0.5, size.y - dimensions.y - 36))
		candidates.append(Vector2(CARD_MARGIN, size.y - dimensions.y - 36))
		candidates.append(Vector2(CARD_MARGIN, CARD_MARGIN))
	var best := Vector2.ZERO
	var best_score := INF
	var lower := Vector2.ONE * CARD_MARGIN
	var upper := (size - dimensions - lower).max(lower)
	for candidate: Vector2 in candidates:
		var point := candidate.clamp(lower, upper)
		var rectangle := Rect2(point, dimensions)
		var score := 0.0
		if _target.has_area():
			score += rectangle.intersection(_target.grow(12)).get_area() * 100.0
			var endpoints := _nearest_edges(rectangle, _target)
			score += absf(endpoints[0].distance_to(endpoints[1]) - TARGET_GAP) * 6.0
		for reserved: Rect2 in _avoid_rects:
			score += rectangle.intersection(reserved.grow(12)).get_area() * 100.0
		if _drag_source.has_area() and _drag_arrow.intersects_rect(rectangle.grow(10)):
			score += 50000.0
		# Small stability bias prevents flipping sides while the camera settles.
		score += point.distance_to(_card_position) * 0.01 if _target.has_area() else float(candidates.find(candidate))
		if score < best_score:
			best_score = score
			best = point
	return best

func _nearest_edges(card: Rect2, target: Rect2) -> PackedVector2Array:
	var from := card.get_center()
	var to := target.get_center()
	if card.end.x <= target.position.x:
		from.x = card.end.x
		to.x = target.position.x
	elif target.end.x <= card.position.x:
		from.x = card.position.x
		to.x = target.end.x
	else:
		from.x = clampf(target.get_center().x, card.position.x + 20, card.end.x - 20)
		to.x = clampf(from.x, target.position.x, target.end.x)
	if card.end.y <= target.position.y:
		from.y = card.end.y
		to.y = target.position.y
	elif target.end.y <= card.position.y:
		from.y = card.position.y
		to.y = target.end.y
	else:
		from.y = clampf(target.get_center().y, card.position.y + 20, card.end.y - 20)
		to.y = clampf(from.y, target.position.y, target.end.y)
	return PackedVector2Array([from, to])

func _update_arrow(card: Rect2) -> void:
	_arrow_visible = false
	_arrow.visible = false
	_drag_arrow.hide()
	if not _target.has_area() or _blocked: return
	if _drag_source.has_area():
		_arrow_from = _drag_source_point
		_arrow_to = _target.get_center()
		_drag_arrow.modulate.a = 1.0 if _active else _appearance
		_drag_arrow.show()
		_arrow_visible = true
		return
	if card.intersects(_target): return
	var endpoints := _nearest_edges(card, _target)
	var direction := (endpoints[1] - endpoints[0]).normalized()
	_arrow_to = endpoints[1] - direction * 7.0
	var length := minf(MAX_ARROW_LENGTH, endpoints[0].distance_to(_arrow_to) - 5.0)
	_arrow_from = _arrow_to - direction * length
	_arrow_visible = length >= 18.0
	_arrow.visible = _arrow_visible
	# The pointer stays visible while the dialogue card changes targets.
	_arrow.modulate.a = 1.0 if _active else _appearance
	if _arrow_visible:
		var requires_action := not _hint_only and str(_steps[_display_index].get("action", "continue")) != "continue"
		_arrow.point_to(_arrow_to, direction.angle(), length, requires_action)

func handles_viewport_point(point: Vector2) -> bool:
	if not _active or not is_visible_in_tree() or not point.is_finite(): return false
	for path: String in ["Card/Content/Actions/Continue", "Card/Content/Actions/Skip"]:
		var button: Button = _ui.get_node(path)
		if not button.is_visible_in_tree(): continue
		var local := button.get_global_transform_with_canvas().affine_inverse() * point
		if Rect2(Vector2.ZERO, button.size).has_point(local): return true
	return false

func inspection() -> Dictionary:
	return {"active": _active, "step": {} if _steps.is_empty() else _steps[_index].duplicate(true), "index": _index, "count": _steps.size(), "completed": _completed, "blocked": _blocked, "hint_only": _hint_only, "target_rect": _target, "history": _history.duplicate(true), "fixed_wait_seconds": 0, "blocks_desktop": _active and not _hint_only, "portrait": "res://assets/image/textures/studio/desk/portrait_67.png", "card_rect": _ui.get_node("Card").get_rect() if _ui != null else Rect2(), "avoid_rects": _avoid_rects.duplicate(), "arrow_visible": _arrow_visible, "arrow_length": _arrow_from.distance_to(_arrow_to) if _arrow_visible else 0.0, "arrow":_arrow.inspection() if _arrow != null else {}, "return_overview":_return_overview, "transitioning": _transitioning, "appearance": _appearance, "display_index": _display_index}

func default_steps() -> Array[Dictionary]:
	return [
		{"id":"identity", "title":"LOC_A_JOB_6E979BE1", "text":"LOC_YOU_ARE_THE_STUDIO_S_PRINT_EDITOR_FF8B8683", "action":"continue"},
		{"id":"work", "title":"LOC_YOUR_DRAFT_B0E0C947", "text":"LOC_PUT_AN_EXPRESSION_INTO_A_MEME_ADJUST_FFBF95D7", "action":"continue"},
		{"id":"goals", "title":"LOC_FOUR_WAYS_TO_FINISH_648EFA2D", "text":"LOC_OWN_THE_WORLD_LET_AN_UNCONTROLLED_LINEAGE_FCB2FB17", "action":"continue"},
		{"id":"pickup", "title":"LOC_THE_PHONE_IS_RINGING_340485E6", "text":"LOC_ANSWER_THE_PHONE_THREE_STARTING_DRAFTS_ARE_B98B5B3A", "action":"phone_pickup", "target":"fax/pickup"},
		{"id":"starter", "title":"LOC_TAKE_A_DRAFT_72393BB5", "text":"LOC_CHOOSE_A_STARTING_MEME_IN_THE_CALL_D26D5127", "action":"starter_chosen", "target":"fax/options"},
		{"id":"hangup", "title":"LOC_END_THE_CALL_ADD703A6", "text":"LOC_HANG_UP_AND_RETURN_TO_THE_DESK_FA41627B", "action":"startup_finished", "target":"fax/hangup"},
		{"id":"machines", "title":"LOC_FAX_AND_REPORTS_5CF0BA35", "text":"LOC_THE_FAX_RECEIVES_REPORTS_AND_CARDS_CLICK_FF09A1DF", "action":"continue", "target":"desktop/fax"},
		{"id":"printer", "title":"LOC_PRINTER_7D6376EF", "text":"LOC_THE_PRINTER_KEEPS_YOUR_WORK_LOG_THE_5F08155E", "action":"continue", "target":"desktop/printer"},
		{"id":"monitor", "title":"LOC_MONITOR_1A13EA59", "text":"LOC_THE_MONITOR_WATCHES_YOUR_MEMES_AND_POINTS_80B39D7D", "action":"continue", "target":"desktop/monitor"},
		{"id":"speed", "title":"LOC_TIME_CONTROLS_4A53DBA9", "text":"LOC_TRY_PAUSE_NORMAL_SPEED_OR_FAST_FORWARD_DF69CA7C", "action":"speed_changed", "target":"speed"},
		{"id":"edit", "title":"LOC_EDIT_SHEET_EFF562AB", "text":"LOC_PULL_OUT_THE_EDIT_SHEET_PATCHES_CLIP_C10C8769", "action":"sheet_selected", "match":{"id":"edit"}, "target":"sheet/edit"},
		{"id":"module", "title":"LOC_CLIP_IN_A_PATCH_111ED358", "text":"LOC_CLIP_ONE_OF_YOUR_PATCH_SLIPS_INTO_E3D38B97", "action":"module_installed", "target":"editor/clips"},
		{"id":"context", "title":"LOC_CONTEXT_SLICES_82B22623", "text":"LOC_PULL_OUT_THE_CULTIVATE_SHEET_AND_INSPECT_DAD209DF", "action":"sheet_selected", "match":{"id":"cultivate"}, "target":"sheet/cultivate"},
		{"id":"context_item", "title":"LOC_GIVE_THE_EXPRESSION_A_CONTEXT_020970BF", "text":"LOC_PLACE_AN_AVAILABLE_ITEM_INTO_ITS_MATCHING_92ABA624", "action":"context_installed", "target":"context/slot"},
		{"id":"spread", "title":"LOC_SPREAD_SHEET_9D66347F", "text":"LOC_PULL_OUT_THE_SPREAD_SHEET_ABILITIES_GROW_5530382E", "action":"sheet_selected", "match":{"id":"spread"}, "target":"sheet/spread"},
		{"id":"skill", "title":"LOC_BUY_AN_ABILITY_697FC774", "text":"LOC_CHOOSE_AN_ABILITY_YOU_CAN_AFFORD_A_97E2AFCC", "action":"skill_purchased", "target":"spread/skill"},
		{"id":"publish", "title":"LOC_SEND_TO_PRINT_832C1ECB", "text":"LOC_CONFIRM_THE_DRAFT_ON_THE_EDIT_SHEET_66DB30DA", "action":"publish_requested", "target":"editor/publish"},
		{"id":"country", "title":"LOC_CHOOSE_A_DESTINATION_4678E011", "text":"LOC_CHOOSE_A_COUNTRY_ON_THE_MAP_SHEET_6A9D0811", "action":"country_selected", "target":"map/country"},
		{"id":"confirm", "title":"LOC_START_CIRCULATING_4530C87E", "text":"LOC_CLICK_THE_CHECKED_BUBBLE_ABOVE_A_COUNTRY_B1C53CA4", "action":"published", "target":"map/confirm"}
	]

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
