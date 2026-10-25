class_name DeskFaxStation
extends Control

signal camera_focus_requested(mode: String)
var _fixed_desktop_mode := false
var _camera_reveal_allowed := false
var _camera_pending_archive: Dictionary = {}

signal read_completed(instance_id: String)
signal focus_changed(focused: bool)
signal call_changed(record: Dictionary)
signal starter_selected(preset_id: String)
signal startup_finished(preset_id: String)
signal material_requested(record: Dictionary, point: Vector2)
signal history_selected(record: Dictionary)
signal details_changed(record: Dictionary)
signal event_output_started(record: Dictionary, page: Control)
signal event_output_delivered(record: Dictionary, page: Control)

const RewardSlip := preload("res://scripts/presentation/studio/paper/desk_event_material_slip.gd")
const OutputPage := preload("res://scripts/presentation/studio/devices/fax/desk_fax_output_page.gd")

const CallSession := preload("res://scripts/presentation/studio/devices/fax/fax_call_session.gd")
const OutputController := preload("res://scripts/presentation/studio/devices/fax/fax_output_controller.gd")
const StationView := preload("res://scripts/presentation/studio/devices/fax/fax_station_view.gd")
const A4_RATIO = StationView.A4_RATIO
const KEY_ZONES = StationView.KEY_ZONES
const REPLIES = CallSession.REPLIES
var _call_session := CallSession.new()
var _view := StationView.new()
var _output := OutputController.new()

@export var feed_duration: float = 0.65
@export var retract_duration: float = 0.55
@export var focus_duration: float = 0.22

var _bound_machine: TextureRect
var _bound_visible: bool = true
var _machine_hidden: bool = false
var _machine_rect := Rect2(24, 12, 300, 240)
var _viewport_rect := Rect2(0, 0, 1280, 720)
var _source_mouth := Rect2()
var _textures: Dictionary = {}
var _archived_event: Dictionary = {}
var _diagnostic: String = "仅本地接线，不拨打真实电话。"
var _focused: bool = false
var _focus_mode: String = ""
var _blocked: bool = false
var _stamp_armed: bool = false
var _built: bool = false
var _focus_tween: Tween
var _paused_tweens: Array[Tween] = []
var _focus_progress: float = 0.0:
	set(value):
		_focus_progress = clampf(value, 0.0, 1.0)
		if _built: _layout_scene()
var _paper_text: String = ""
var _seal_center := Vector2.ZERO
var _seal_radius: float = 18.0
var _paper_height: float = 160.0
var _paper_polygon := PackedVector2Array()
var _reward_rows: Array[Dictionary] = []
var _reward_slips: Dictionary = {}
var _requesting_slip: Control
var _page_keyboard_shortcuts := false
var _output_stack_area := Rect2()
var _handwritten_font: Font
var _external_details := false
var viewport_exclusion: Callable


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	if _call_session.contacts.is_empty(): set_contacts([])
	else: _refresh_contacts()
	_layout_scene()


func _exit_tree() -> void:
	_restore_machine()


func configure(textures: Dictionary = {}, ui_theme: Theme = null, options: Dictionary = {}) -> void:
	_build()
	_textures = textures.duplicate()
	_page_keyboard_shortcuts = options.get("page_keyboard_shortcuts", false) == true
	if ui_theme != null: theme = ui_theme
	for field in ["feed_duration", "retract_duration", "focus_duration"]:
		if options.get(field) is float or options.get(field) is int:
			var value := float(options[field])
			if is_finite(value) and value > 0.0: set(field, value)
	_view.display.texture = _textures.get("machine") as Texture2D
	_view.portrait.texture = _textures.get("portrait_67") as Texture2D
	_view.player_portrait.texture = _textures.get("portrait_player") as Texture2D
	_view.seal.texture = _textures.get("stamp") as Texture2D
	_view.book_art.texture = _textures.get("phonebook") as Texture2D
	_view.stamp_art.texture = _textures.get("stamp_prop") as Texture2D
	if _view.book_art.texture != null:
		_view.book.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_view.contact_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_view.contact_list.add_theme_color_override("font_color", Color("252a23"))
	_output.set_durations(feed_duration, retract_duration)
	_output.set_page_theme(theme)
	if options.get("source_mouth") is Rect2: _source_mouth = options.source_mouth
	_layout_scene()


func bind_machine(machine: TextureRect, source_mouth: Rect2 = Rect2()) -> void:
	_build()
	_restore_machine()
	_bound_machine = machine
	if machine != null:
		_bound_visible = machine.visible
		_view.display.texture = machine.texture
		_machine_rect = machine.get_global_rect()
		if _focused and _focus_mode == "phone":
			machine.hide()
			_machine_hidden = true
	if source_mouth.has_area(): _source_mouth = source_mouth
	_layout_scene()


func set_fixed_desktop_mode(value: bool) -> void:
	_fixed_desktop_mode = value
	if value: _restore_machine()
	if _built: _layout_scene()


func set_continuous_output(value: bool) -> void:
	_build()
	_output.set_continuous_output(value)
	if value: _apply_handwriting()
	_refresh()


func set_output_stack_area(area: Rect2) -> void:
	if not area.position.is_finite() or not area.size.is_finite() or area.size.x < 64.0 or area.size.y < 96.0: return
	_output_stack_area = area
	if _built: _layout_scene()


func set_external_details(value: bool) -> void:
	_external_details = value
	if _built: _refresh()

func component_details(mode: String = "phone") -> Dictionary:
	if mode in ["paper","archive"]: return history_details()
	var log_lines := PackedStringArray()
	for record: Dictionary in _call_session.call_log: log_lines.append(str(record.get("text","")))
	return {"title":"电话簿" if mode == "phonebook" else "传真机", "description":_physical_key_legend(),
		"status":_diagnostic, "log":"\n".join(log_lines), "number":_call_session.dialed_number, "contact_count":_call_session.contacts.size(),
		"contacts":_call_session.contacts.duplicate(true), "options":_call_session.starter_options.duplicate(true) if _starter_call() else Array(REPLIES),
		"reply_enabled":_can_phone() and _call_session.state == "connected", "call_state":_call_session.state, "npc_text":_npc_source_text()}


func history_details() -> Dictionary:
	var record: Dictionary = _archived_event if not _archived_event.is_empty() else _output.last_read
	return {"title":str(record.get("title","事件纸堆")), "description":str(record.get("narrative","来信打印后留在这里，点露出的页签翻看。")),
		"instance_id":str(record.get("instance_id","")), "hour":str(record.get("hour","")),
		"impact":str(record.get("impact_text","")), "effect":str(record.get("effect_text","")), "mentor":str(record.get("mentor_comment","")), "read_only":true,
		"gesture":"点击露出的页签翻阅；滚轮继续翻更早或更新的来信。",
		"history":_output.output_pages.map(func(page): return {"instance_id":str(page.event.get("instance_id","")),"title":str(page.event.get("title","")),"hour":page.event.get("hour",0)})}


func select_history(instance_id: String) -> bool:
	for page: Control in _output.output_pages:
		if str(page.event.get("instance_id", "")) == instance_id: return view_archived_event(page.event)
	return false

func browse_history(direction: int) -> bool:
	if _output.output_pages.is_empty() or direction == 0: return false
	var selected := _output.output_pages.size() - 1
	for index in _output.output_pages.size():
		if str(_output.output_pages[index].event.get("instance_id", "")) == str(_archived_event.get("instance_id", "")): selected = index
	var next := clampi(selected + direction, 0, _output.output_pages.size() - 1)
	return select_history(str(_output.output_pages[next].event.get("instance_id", "")))

func select_contact(index: int) -> bool:
	var selected: bool = _call_session.select_contact(index, _can_phone())
	if selected: _refresh_call_view()
	return selected

func _output_at(viewport_point: Vector2) -> Control:
	# Exposed tabs are checked before paper bodies, so an older sheet stays reachable.
	for index in range(_output.output_pages.size() - 1, -1, -1):
		var page: Control = _output.output_pages[index]
		if page.visible and Geometry2D.is_point_in_polygon(viewport_point, StationView.global_polygon(page, page.history_tab_rect())): return page
	var selected := _page_for_event(str(_archived_event.get("instance_id", "")))
	if selected != null and Geometry2D.is_point_in_polygon(viewport_point, StationView.global_polygon(selected, Rect2(Vector2.ZERO, selected.size))): return selected
	for index in range(_output.output_pages.size() - 1, -1, -1):
		var page: Control = _output.output_pages[index]
		if page.visible and Geometry2D.is_point_in_polygon(viewport_point, StationView.global_polygon(page, Rect2(Vector2.ZERO, page.size))): return page
	return null

func hover_details(viewport_point: Vector2) -> String:
	if not viewport_point.is_finite(): return ""
	for control: Button in _view.keys + [_view.dial_button,_view.pickup_button,_view.hangup_button]:
		if control.is_visible_in_tree() and Rect2(Vector2.ZERO,control.size).has_point(control.get_global_transform_with_canvas().affine_inverse()*viewport_point):
			return _key_action_label(control)
	var page := _output_at(viewport_point)
	if page != null:
		var record: Dictionary = page.event
		return "%s · H%s · %s" % [DeskLocalization.text(str(record.get("title", ""))), str(record.get("hour", "?")), str(record.get("instance_id", ""))]
	return ""


func _apply_handwriting() -> void:
	var path := "res://assets/image/fonts/handwritten_font.tres"
	if not ResourceLoader.exists(path): return
	_handwritten_font = load(path) as Font
	if _handwritten_font == null: return
	var paper_theme := theme.duplicate() as Theme if theme != null else Theme.new()
	paper_theme.default_font = _handwritten_font
	theme = paper_theme
	_output.set_page_theme(paper_theme)

func reveal_after_camera(mode: String) -> void:
	_camera_reveal_allowed = true
	if mode == "paper": focus_paper()
	elif mode == "archive": view_archived_event(_camera_pending_archive)
	else: focus()
	_camera_reveal_allowed = false

func layout_station(machine_rect: Rect2, viewport_rect: Rect2, source_mouth: Rect2 = Rect2()) -> void:
	_build()
	_machine_rect = machine_rect
	_viewport_rect = viewport_rect
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = viewport_rect.position
	size = viewport_rect.size.max(Vector2.ZERO)
	if source_mouth.has_area(): _source_mouth = source_mouth
	_layout_scene()


func receive_event(event: Dictionary) -> bool:
	_build()
	if not _output.enqueue(event):
		if not _output.last_error.is_empty():
			_diagnostic = _output.last_error
			_refresh()
		return false
	if _focus_mode == "archive" and not _output.continuous_output: close_focus()
	if event.get("contacts") is Array:
		for contact: Variant in event.contacts:
			if contact is Dictionary: add_contact(contact)
	if event.get("contact") is Dictionary: add_contact(event.contact)
	_output.dispatch_pending()
	return true


func restore_output_history(events: Array) -> int:
	_build()
	return _output.restore_history(events)


func sync_reward_state(rows: Array) -> void:
	_reward_rows.clear()
	for row: Variant in rows:
		if row is Dictionary: _reward_rows.append(row.duplicate(true))
	_sync_reward_slips()

func confirm_material_request(record: Dictionary, accepted: bool) -> void:
	var key := _reward_key(record)
	var slip: Control = _reward_slips.get(key, _requesting_slip)
	if is_instance_valid(slip):
		slip.set_committed(accepted)
		if accepted:
			slip.hide()
			slip.queue_free()
			_reward_slips.erase(key)

func _reward_key(row: Dictionary) -> String:
	return "%s/%s/%s" % [str(row.get("instance_id", "")), str(row.get("kind", "")), str(row.get("id", ""))]

func _sync_reward_slips() -> void:
	if not _built or _view.reward_tray == null: return
	if _output.continuous_output:
		_sync_printed_cards()
		return
	var wanted := {}
	var active_index := 0
	var tray_index := 0
	var active_id := str(_output.active_event.get("instance_id", ""))
	for row: Dictionary in _reward_rows:
		if row.get("requested", false): continue
		var current: bool = str(row.get("instance_id", "")) == active_id and not active_id.is_empty()
		if not current and not row.get("acknowledged", false): continue
		var key := _reward_key(row)
		wanted[key] = true
		var slip: Control
		if _reward_slips.has(key):
			slip = _reward_slips[key]
		else:
			slip = RewardSlip.new()
			slip.name = "RewardSlip"+str(_reward_slips.size())
			(_view.sheet if current else _view.reward_tray).add_child(slip)
			slip.configure(row, self, theme)
			slip.dropped.connect(_request_material)
			_reward_slips[key] = slip
		if not slip.is_dragging():
			var host := _view.sheet if current else _view.reward_tray
			if slip.get_parent() != host: slip.reparent(host, false)
			slip.rotation = 0.0
			if current:
				var width := maxf(34.0,minf(82.0,(_view.sheet.size.x-_seal_radius*2-34.0)/maxi(1,_active_reward_count())))
				slip.size = Vector2(width,44.0 if _view.sheet.size.x > 250 else 36.0)
				slip.position = Vector2(9.0+active_index*(width+3.0),_seal_center.y-slip.size.y*.5+_view.sheet.size.y-_paper_height)
				active_index += 1
			else:
				slip.size = Vector2(82,52)
				slip.position = Vector2((tray_index%2)*86,(tray_index/2)*20)
				slip.rotation = deg_to_rad(float((tray_index%3)-1)*2.0)
				tray_index += 1
		slip.visible = _focus_mode != "archive" and (not current or _output.event_state == "ready")
		slip.set_interaction_enabled(slip.visible and not _blocked and _focus_mode != "phone" and _output.event_state != "retracting")
	_view.reward_tray.visible = tray_index > 0 and _focus_mode not in ["archive", "phone"]
	_view.reward_tray.size.y = maxf(52.0,ceilf(float(tray_index)/2.0)*20.0+32.0)
	for key in _reward_slips.keys():
		if not wanted.has(key):
			_reward_slips[key].queue_free()
			_reward_slips.erase(key)

func _page_for_event(instance_id: String) -> Control:
	return _output.page_for_event(instance_id)

func _sync_printed_cards() -> void:
	_view.reward_tray.hide()
	var wanted := {}
	var per_page := {}
	for row: Dictionary in _reward_rows:
		if row.get("requested", false): continue
		var page := _page_for_event(str(row.get("instance_id", "")))
		if page == null: continue
		var key := _reward_key(row)
		wanted[key] = true
		var slip: Control = _reward_slips.get(key)
		if not is_instance_valid(slip):
			slip = RewardSlip.new()
			slip.name = "PrintedMaterial" + str(_reward_slips.size())
			page.add_child(slip)
			slip.configure(row, self, theme)
			slip.dropped.connect(_request_material)
			_reward_slips[key] = slip
		slip.record = row.duplicate(true)
		var page_key := str(page.get_instance_id())
		var index := int(per_page.get(page_key, 0))
		per_page[page_key] = index + 1
		if not slip.is_dragging():
			if slip.get_parent() != page: slip.reparent(page, false)
			var positions: Dictionary = page.get_meta("attachment_positions", {})
			var card_rect: Rect2 = positions.get(str(row.get("kind", "")) + "/" + str(row.get("id", "")), Rect2(8,116 + index * 94,72,88))
			slip.size = card_rect.size
			slip.position = card_rect.position
			slip.rotation = deg_to_rad(float((index % 3) - 1) * 2.0)
		slip.visible = true
		var selected_source := _focus_mode != "archive" or str(row.get("instance_id", "")) == str(_archived_event.get("instance_id", ""))
		slip.set_interaction_enabled(page != _output.feeding_page and not _blocked and selected_source)
	for key: String in _reward_slips.keys():
		if not wanted.has(key):
			_reward_slips[key].queue_free()
			_reward_slips.erase(key)

func _active_reward_count() -> int:
	var count := 0
	for row: Dictionary in _reward_rows:
		if str(row.get("instance_id", "")) == str(_output.active_event.get("instance_id", "")) and not row.get("requested", false): count += 1
	return count

func _request_material(record: Dictionary, point: Vector2) -> void:
	var local := get_global_transform_with_canvas().affine_inverse()*point
	var origin_page := _page_for_event(str(record.get("instance_id", "")))
	var on_origin := origin_page != null and Geometry2D.is_point_in_polygon(point, StationView.global_polygon(origin_page, Rect2(Vector2.ZERO, origin_page.size)))
	if _blocked or not Rect2(Vector2.ZERO,size).has_point(local) or (on_origin if _output.continuous_output else (_focus_mode == "archive" or Geometry2D.is_point_in_polygon(point,_paper_polygon))):
		confirm_material_request(record, false)
		return
	_requesting_slip = _reward_slips.get(_reward_key(record))
	material_requested.emit(record.duplicate(true), point)
	_requesting_slip = null


func offer_starters(options: Array, selected_id: String = "") -> bool:
	_build()
	if not _output.active_event.is_empty() or not _output.pending_events.is_empty(): return false
	if not _call_session.offer_starters(options, selected_id): return false
	focus()
	_refresh_call_view()
	return true


func confirm_starter(preset_id: String) -> bool:
	_call_session.set_context(_output.last_read)
	var confirmed: bool = _call_session.confirm_starter(preset_id, _can_phone())
	if confirmed: _refresh_call_view()
	return confirmed


func reject_starter(message: String) -> void:
	_call_session.reject_starter(message)
	_refresh_call_view()


func clear_starter_offer() -> void:
	for slip in _reward_slips.values(): slip.queue_free()
	_reward_slips.clear()
	_reward_rows.clear()
	_call_session.clear_starter_offer()
	_refresh()


func _starter_call() -> bool:
	return _call_session.starter_call(_can_phone())


func view_archived_event(event: Dictionary) -> bool:
	_build()
	if _blocked: return false
	if not _output.continuous_output and (_output.busy()):
		_diagnostic = "先处理当前待阅情报，再翻历史档案。"
		if _output.event_state == "ready": focus_paper()
		else: _refresh()
		return false
	if str(event.get("instance_id","")).strip_edges().is_empty() or not event.get("title") is String or not event.get("narrative") is String:
		_diagnostic = "历史记录缺少真实编号、标题或正文。"
		_refresh()
		return false
	if _fixed_desktop_mode and not _camera_reveal_allowed and not (_focused and _focus_mode == "archive"):
		_camera_pending_archive = event.duplicate(true)
		camera_focus_requested.emit("archive")
		return true
	var was_focused := _focused
	_archived_event = event.duplicate(true)
	_output.select_history_page(str(event.instance_id))
	history_selected.emit(_archived_event.duplicate(true))
	_restore_machine()
	_stamp_armed = false
	_focused = true
	_focus_mode = "archive"
	_tween_focus(1.0)
	_refresh()
	if not was_focused: focus_changed.emit(true)
	return true


func focus() -> bool:
	_build()
	if _blocked or (_focused and _focus_mode == "phone"): return false
	if _fixed_desktop_mode and not _camera_reveal_allowed:
		camera_focus_requested.emit("phone")
		return true
	var was_focused := _focused
	_archived_event = {}
	_focused = true
	_focus_mode = "phone"
	if is_instance_valid(_bound_machine) and not _fixed_desktop_mode:
		if not _machine_hidden: _bound_visible = _bound_machine.visible
		_bound_machine.hide()
		_machine_hidden = true
	_tween_focus(1.0)
	_refresh()
	if not was_focused: focus_changed.emit(true)
	return true


func focus_paper() -> bool:
	if _blocked or _output.event_state != "ready" or _output.active_event.is_empty() or (_focused and _focus_mode == "paper"): return false
	if _fixed_desktop_mode and not _camera_reveal_allowed:
		camera_focus_requested.emit("paper")
		return true
	var was_focused := _focused
	_restore_machine()
	_focused = true
	_focus_mode = "paper"
	_tween_focus(1.0)
	_refresh()
	if not was_focused: focus_changed.emit(true)
	return true


func close_focus() -> bool:
	if not _focused: return false
	_focused = false
	_stamp_armed = false
	if _focus_mode == "archive":
		_output.restore_page_order()
		_archived_event = {}
		_focus_mode = ""
		if _focus_tween != null and _focus_tween.is_valid(): _focus_tween.kill()
		_focus_progress = 0.0
		_restore_machine()
		_refresh()
		focus_changed.emit(false)
		return true
	_tween_focus(0.0)
	_refresh()
	focus_changed.emit(false)
	return true


func set_interaction_blocked(blocked: bool) -> void:
	if _blocked == blocked: return
	_blocked = blocked
	_output.set_blocked(blocked)
	if blocked:
		if _focus_tween != null and _focus_tween.is_valid() and _focus_tween.is_running():
			_focus_tween.pause()
			_paused_tweens.append(_focus_tween)
	else:
		for tween in _paused_tweens:
			if tween != null and tween.is_valid(): tween.play()
		_paused_tweens.clear()
	_stamp_armed = false if blocked else _stamp_armed
	_refresh()


func stamp() -> bool:
	if _blocked or _focus_mode == "archive" or (_focused and _focus_mode == "phone"): return false
	if not _output.retract(): return false
	_stamp_armed = false
	_view.seal.visible = _view.seal.texture != null
	_view.seal_text.visible = _view.seal.texture == null
	_refresh()
	return true


func arm_stamp() -> bool:
	if _output.continuous_output: return false
	if _blocked or _focus_mode == "archive" or (_focused and _focus_mode == "phone") or _output.event_state != "ready" or _output.active_event.is_empty(): return false
	_stamp_armed = true
	_diagnostic = "印章已拿取；对准纸张右下的收阅圆框。"
	_refresh()
	return true


func stamp_at(global_position: Vector2) -> bool:
	if not is_finite(global_position.x) or not is_finite(global_position.y): return false
	var local := _view.sheet.get_global_transform_with_canvas().affine_inverse() * global_position
	if local.distance_to(_seal_center) > _seal_radius: return false
	return stamp()


func set_contacts(contacts: Array) -> void:
	_call_session.set_contacts(contacts)
	_refresh_contacts()


func add_contact(contact: Dictionary) -> bool:
	var added: bool = _call_session.add_contact(contact)
	if added: _refresh_contacts()
	return added


func keypad_key(key: String) -> bool:
	if key in ["call", "dial"]: return dial()
	if key == "pickup": return pickup()
	if key == "hangup": return hangup()
	var accepted: bool = _call_session.keypad_key(key, _can_phone())
	if accepted: _refresh_call_view()
	return accepted


func dial() -> bool:
	_call_session.set_context(_output.last_read)
	var accepted: bool = _call_session.dial(_can_phone())
	_refresh_call_view()
	return accepted


func pickup() -> bool:
	_call_session.set_context(_output.last_read)
	var accepted: bool = _call_session.pickup(_can_phone())
	_refresh_call_view()
	return accepted


func hangup() -> bool:
	_call_session.set_context(_output.last_read)
	var accepted: bool = _call_session.hangup(not _blocked and _focused and _focus_mode == "phone", _can_phone())
	_refresh_call_view()
	return accepted


func choose_response(index: int) -> bool:
	_call_session.set_context(_output.last_read)
	var accepted: bool = _call_session.choose_response(index, _can_phone())
	_refresh_call_view()
	return accepted


func reset_station() -> void:
	if _focus_tween != null and _focus_tween.is_valid(): _focus_tween.kill()
	_paused_tweens.clear()
	var was_focused := _focused
	_focused = false
	_focus_mode = ""
	_focus_progress = 0.0
	_restore_machine()
	_output.reset()
	_archived_event = {}
	_paper_text = ""
	for slip in _reward_slips.values(): slip.queue_free()
	_reward_slips.clear()
	_reward_rows.clear()
	_stamp_armed = false
	_diagnostic = "情报收件箱已重同步。"
	_call_session.reset()
	_refresh_contacts()
	_refresh()
	if was_focused: focus_changed.emit(false)


func inspection() -> Dictionary:
	var seal_global := _view.sheet.get_global_transform_with_canvas()*_seal_center if _built else Vector2.ZERO
	var key_points: Dictionary = {}
	var key_rects: Dictionary = {}
	var physical_keys: Dictionary = {}
	if _built:
		for control in _view.keys+[_view.dial_button,_view.pickup_button,_view.hangup_button]:
			key_points[str(control.name)] = control.get_global_transform_with_canvas()*(control.size*.5)
			key_rects[str(control.name)] = control.get_global_rect()
			var font: Font = control.get_theme_font("font","Button")
			var font_size: int = control.get_theme_font_size("font_size","Button")
			var transform: Transform2D = control.get_global_transform_with_canvas()
			physical_keys[str(control.name)] = {"text":control.text,"action":str(control.get_meta("physical_action","")),"label":_key_action_label(control),"size":control.size,"font_size":font_size,"text_width":font.get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x,"font_height":font.get_height(font_size),"screen_font_height":font.get_height(font_size)*transform.basis_xform(Vector2.UP).length(),"icon":control.has_node("HanddrawnPhoneAction")}
	var mouth: Dictionary = _mouth_geometry() if _built else {}
	return {
		"continuous_output":_output.continuous_output,"output_direction":"up" if _output.continuous_output else "down","output_stack_area":_output_stack_area,
		"stack_pages":_output.inspection(_output_stack_area),"feeding_page":_output.feeding_page.inspection() if is_instance_valid(_output.feeding_page) else {},"launch":_output.output_geometry.duplicate(),"continuous_physical_page":true,"post_delivery_reposition":false,"history_tabs":true,"external_details":_external_details,"mouth_local":mouth,"mouth_viewport":get_global_transform_with_canvas() * mouth.get("origin",Vector2.ZERO),
		"paper_source_pixels_per_world_unit":OutputPage.SOURCE_PIXELS_PER_UNIT,"handwritten_font_bound":_handwritten_font != null,
		"event_state":_output.event_state,"active_event":_output.active_event.duplicate(true),"queue":_output.pending_events.duplicate(true),"completed":_output.read_event_ids.duplicate(),
		"fixed_desktop_mode":_fixed_desktop_mode,"device_moves_on_focus":not _fixed_desktop_mode,"feed_progress":_output.feed_progress,"focused":_focused,"focus_mode":_focus_mode,"focus_progress":_focus_progress,"blocked":_blocked,
		"stamp_armed":_stamp_armed,"busy":_output.event_state in ["feeding","retracting"],
		"paper_rect":_output.feeding_page.get_global_rect() if is_instance_valid(_output.feeding_page) else (_view.sheet.get_global_rect() if _built else Rect2()),"paper_full_size":_output.output_geometry.get("size",Vector2.ZERO) if is_instance_valid(_output.feeding_page) else (Vector2(_view.sheet.size.x,_paper_height) if _built else Vector2.ZERO),
		"paper_visible":(_output.feeding_page.visible and _output.feed_progress > 0.0) if is_instance_valid(_output.feeding_page) else (_view.sheet.visible if _built else false),"paper_polygon":StationView.global_polygon(_output.feeding_page,Rect2(Vector2.ZERO,_output.feeding_page.size)) if is_instance_valid(_output.feeding_page) else _paper_polygon.duplicate(),"paper_rotation":_output.feeding_page.rotation if is_instance_valid(_output.feeding_page) else (_view.sheet.rotation if _built else 0.0),
		"paper_text":_paper_text,"rendered_paper_text":(_view.paper_meta.text+"\n" if _view.paper_meta.visible else "")+_view.paper_title.text+"\n\n"+_view.body.text if _built else "","paper_view":"archive" if _focus_mode == "archive" else ("full" if _focus_mode == "paper" and _focus_progress > .5 else "compact"),"read_only":_focus_mode == "archive","archived_event":_archived_event.duplicate(true),"paper_scroll_active":_view.body.scroll_active if _built else false,"paper_border_widths":[(_view.paper.get_theme_stylebox("panel") as StyleBoxFlat).get_border_width(SIDE_LEFT),(_view.paper.get_theme_stylebox("panel") as StyleBoxFlat).get_border_width(SIDE_TOP),(_view.paper.get_theme_stylebox("panel") as StyleBoxFlat).get_border_width(SIDE_RIGHT),(_view.paper.get_theme_stylebox("panel") as StyleBoxFlat).get_border_width(SIDE_BOTTOM)] if _built else [],"paper_shadow_visible":_view.paper_shadow.visible if _built else false,"paper_shadow_size":(_view.paper_shadow.get_theme_stylebox("panel") as StyleBoxFlat).shadow_size if _built else 0,"seal_center":seal_global,"seal_radius":_seal_radius,"seal_rect":Rect2(seal_global-Vector2.ONE*_seal_radius,Vector2.ONE*_seal_radius*2),
		"reward_slips":_reward_slips.values().map(func(slip): return slip.inspection()),"reward_rows":_reward_rows.duplicate(true),
		"physical_keys":physical_keys,"source_mouth":_source_mouth,"source_key_zones":KEY_ZONES,"keyboard_points":key_points,"keyboard_rects":key_rects,
		"machine_rect":_machine_rect,"viewport_rect":_viewport_rect,"call_state":_call_session.state,"number":_call_session.dialed_number,"diagnostic":_diagnostic,
		"contacts":_call_session.contacts.duplicate(true),"call_log":_call_session.call_log.duplicate(true),"last_read":_output.last_read.duplicate(true),
		"pickup_enabled":not _view.pickup_button.disabled if _built else false,"npc_text":_view.conversation.text if _built else "","player_text":_call_session.selected_reply,"dialogue_options":_call_session.starter_options.duplicate(true) if _starter_call() else REPLIES,
		"starter_options":_call_session.starter_options.duplicate(true),"starter_id":_call_session.starter_id,"pending_starter_id":_call_session.pending_starter_id,"startup_done":_call_session.startup_done,
		"dialogue_rect":_view.identity.get_global_rect() if _built else Rect2(),"npc_rect":_view.conversation.get_global_rect() if _built else Rect2(),"player_rect":_view.player_line.get_global_rect() if _built else Rect2(),
		"portrait_67_bound":_view.portrait.texture != null if _built else false,"player_portrait_native":_view.player_portrait.texture == null if _built else false,
		"network_calls":0,"economic_calls":0,"mouse_filter":mouse_filter,"focus_shade_visible":_view.shade.visible if _built else false,
		"nodes":{"sheet":str(_view.sheet.get_path()) if _built else "","keypad":str(_view.phone.get_path()) if _built else "","book":str(_view.book.get_path()) if _built else "","identity":str(_view.identity.get_path()) if _built else "","seal":str(_view.seal_guide.get_path()) if _built else ""}}


func handle_key(event: InputEventKey) -> bool:
	if _blocked or not _focused or not event.pressed or event.echo: return false
	if event.keycode == KEY_ESCAPE:
		close_focus()
		return true
	if _focus_mode != "phone": return false
	if event.keycode == KEY_BACKSPACE: return keypad_key("backspace")
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER: return dial()
	var character := String.chr(event.unicode) if event.unicode > 0 else ""
	return keypad_key(character) if character.length() == 1 else false


func _input(event: InputEvent) -> void:
	if _blocked: return
	if event is InputEventMouse and viewport_exclusion.is_valid() and viewport_exclusion.call(event.position): return
	if _page_keyboard_shortcuts and event is InputEventKey:
		var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		# The integrated page owns these shortcuts even during a focused call.
		if key == KEY_ESCAPE or (key == KEY_D and event.ctrl_pressed): return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and _output.continuous_output:
		if _output_at(event.position) != null and browse_history(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1):
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		for slip in _reward_slips.values():
			if slip.visible and Rect2(Vector2.ZERO,slip.size).has_point(slip.get_global_transform_with_canvas().affine_inverse()*event.position): return
	if event is InputEventKey and handle_key(event):
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _output.continuous_output:
			var page := _output_at(event.position)
			if page != null:
				if view_archived_event(page.event): get_viewport().set_input_as_handled()
				return
		if _can_phone() and _view.book.visible:
			var point: Vector2 = _view.ruled_contacts.get_global_transform_with_canvas().affine_inverse()*event.position
			for row: Dictionary in _view.ruled_contacts.inspection().rows:
				var area := Rect2(row.name_baseline-Vector2(4,12),Vector2(_view.ruled_contacts.size.x*.7,14))
				if area.has_point(point):
					_select_contact(int(row.index))
					get_viewport().set_input_as_handled()
					return
		if (_stamp_armed or _focus_mode == "paper" or not _focused) and stamp_at(event.position):
			get_viewport().set_input_as_handled()
			return
		if not _focused and _output.event_state == "ready" and Geometry2D.is_point_in_polygon(event.position,_paper_polygon):
			if focus_paper(): get_viewport().set_input_as_handled()
		elif not _focused and Geometry2D.is_point_in_polygon(event.position, _machine_polygon()):
			if focus(): get_viewport().set_input_as_handled()


func _build() -> void:
	if _built: return
	_built = true
	_view.name = "FaxStationView"
	add_child(_view)
	_view.build()
	_output.name = "FaxOutputController"
	add_child(_output)
	_output.configure(_view.output_host, theme, _launch_for_event)
	_output.set_durations(feed_duration, retract_duration)
	_output.state_changed.connect(_on_output_state_changed)
	_output.progress_changed.connect(_layout_scene)
	_output.pages_changed.connect(_sync_reward_slips)
	_output.read_completed.connect(read_completed.emit)
	_output.output_started.connect(event_output_started.emit)
	_output.output_delivered.connect(event_output_delivered.emit)
	_view.contact_selected.connect(_select_contact)
	_view.keypad_requested.connect(keypad_key)
	_view.dial_requested.connect(dial)
	_view.pickup_requested.connect(pickup)
	_view.hangup_requested.connect(hangup)
	_view.response_requested.connect(choose_response)
	_view.stamp_requested.connect(arm_stamp)
	_view.close_requested.connect(close_focus)
	_call_session.call_changed.connect(call_changed.emit)
	_call_session.starter_selected.connect(starter_selected.emit)
	_call_session.startup_finished.connect(_on_startup_finished)
	_refresh()


func _english_ui() -> bool:
	return TranslationServer.get_locale().to_lower().begins_with("en")

func _physical_key_legend() -> String:
	return "拨号：呼叫已选号码。接听：拿起听筒。挂断：结束通话。三个听筒图标对应这三个实体键，来信仍会继续打印。"


func _key_action_label(button: Button) -> String:
	var action := str(button.get_meta("physical_action", ""))
	if _english_ui(): return {"dial":"Dial", "answer":"Answer", "hangup":"Hang up", "backspace":"Delete last digit"}.get(action,button.text)
	return {"dial":"拨号", "answer":"接听", "hangup":"挂断", "backspace":"删除一位"}.get(action,button.text)


func _launch_for_event(record: Dictionary) -> Dictionary:
	var mouth := _mouth_geometry()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(record.get("instance_id", "")))
	var spatial := get_viewport() is SubViewport
	var angle := float(mouth.angle) + (0.0 if spatial else rng.randf_range(-.045, .045))
	var width := float(mouth.width)
	var velocity := Vector2.ZERO if spatial else Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-5.0, 2.0))
	var attachments := _plan_attachments(record, width)
	return {"origin":mouth.origin,"angle":angle,"size":Vector2(width,attachments.height),
		"drift":velocity,"duration_scale":rng.randf_range(.86,1.16),"instance_id":str(record.get("instance_id","")),"attachments":attachments.cards}


func _plan_attachments(event: Dictionary, width: float) -> Dictionary:
	var cards := {}
	var row := 0
	for reward: Dictionary in event.get("design_rewards", []):
		var kind := str(reward.get("kind", ""))
		var dimensions := Vector2(144,78) if kind == "topic" else Vector2(112,82)
		cards[kind + "/" + str(reward.get("id", ""))] = Rect2(Vector2((width-dimensions.x)*.5,116+row*92),dimensions)
		row += 1
	return {"cards":cards,"height":maxf(width*A4_RATIO,128+row*92) if not cards.is_empty() else width*A4_RATIO}


func _update_paper_contents(expanded: bool) -> void:
	var event: Dictionary = _archived_event if _focus_mode == "archive" else _output.active_event
	if event.is_empty():
		_paper_text = ""
		_view.paper_title.text = ""
		_view.body.text = ""
		return
	var meta := DeskLocalization.source_format("情报摘录 / 助手收集  ·  H%s / %s",[str(event.get("hour","?")),str(event.get("origin","未标出处"))])
	var mentor := str(event.get("mentor_comment","先看清消息的出处，再决定要不要发声。"))
	var full_body := DeskLocalization.source_format("%s\n\n作用摘录\n%s\n\n实际作用\n%s\n\n67：%s",[str(event.narrative),str(event.get("impact_text","未提供作用摘要")),str(event.get("effect_text","未提供实际作用记录")),mentor])
	var rewards := str(event.get("reward_text",""))
	if not rewards.is_empty(): full_body += "\n\n" + rewards
	_paper_text = meta+"\n"+str(event.title)+"\n\n"+full_body
	var rendered := DeskLocalization.format_text("%s\n\n作用摘录\n%s\n\n实际作用\n%s\n\n67：%s",[_localized_block(str(event.narrative)),_localized_block(str(event.get("impact_text","未提供作用摘要"))),_localized_block(str(event.get("effect_text","未提供实际作用记录"))),_localized_block(mentor)]) if expanded else DeskLocalization.format_text("%s\n\n67：%s",[_localized_block(str(event.narrative)),_localized_block(mentor)])
	if expanded and not rewards.is_empty(): rendered += "\n\n"+_localized_block(rewards)
	_view.paper_meta.text = DeskLocalization.text(meta)
	_view.paper_title.text = DeskLocalization.text(str(event.title))
	if _view.body.text != rendered: _view.body.text = rendered
	_view.body.scroll_active = expanded
	_view.paper_meta.visible = expanded
	_view.paper_rule.visible = expanded


func _can_phone() -> bool:
	return _focused and _focus_mode == "phone" and not _blocked and not _output.busy()


func _select_contact(index: int) -> void:
	select_contact(index)


func _refresh_contacts() -> void:
	if not _built: return
	_view.ruled_contacts.set_contacts(_call_session.contacts)
	_view.contact_list.hide()
	_view.book_heading.hide()
	_view.contact_list.clear()
	for contact in _call_session.contacts:
		_view.contact_list.add_item("%s  %s" % [str(contact.number), DeskLocalization.text(str(contact.name))])


func _refresh() -> void:
	if not _built: return
	var phone_ui := _focused and _focus_mode == "phone" and not _blocked
	var paper_ui := _focused and _focus_mode in ["paper","archive"] and not _blocked
	_view.shade.visible = _focused and not _blocked and not _fixed_desktop_mode
	for node in [_view.book,_view.phone,_view.identity,_view.status]: node.visible = phone_ui
	_view.close_button.hide()
	_view.stamp_button.hide()
	_view.stamp_art.hide()
	_view.display.visible = not _fixed_desktop_mode and _focus_mode == "phone" and (_focus_progress > 0.0 or _focused)
	_view.sheet.visible = ((not _output.active_event.is_empty() and _output.feed_progress > 0.0) or (_focused and _focus_mode == "archive" and not _archived_event.is_empty())) and _focus_mode != "phone"
	if _output.continuous_output and (_focus_mode != "archive" or _external_details): _view.sheet.hide()
	_view.paper_shadow.visible = _view.sheet.visible
	_view.reward_tray.position = Vector2(clampf(_machine_rect.end.x+10,10,maxf(10,size.x-184)),clampf(_machine_rect.end.y-80,10,maxf(10,size.y-180)))
	_view.reward_tray.size = Vector2(180,160)
	_sync_reward_slips()
	_view.sheet.mouse_filter = Control.MOUSE_FILTER_STOP if paper_ui else Control.MOUSE_FILTER_IGNORE
	_view.body.mouse_filter = Control.MOUSE_FILTER_PASS if paper_ui else Control.MOUSE_FILTER_IGNORE
	_view.number_label.text = _call_session.dialed_number if not _call_session.dialed_number.is_empty() else "号码 / #"
	_view.status.text = DeskLocalization.text(_diagnostic)
	_view.stamp_button.disabled = _blocked or _output.event_state != "ready"
	_view.seal_guide.visible = not _output.continuous_output and _output.event_state != "retracting" and _focus_mode != "archive"
	if _output.continuous_output or _focus_mode == "archive":
		_view.seal.hide()
		_view.seal_text.hide()
	var can_phone := _can_phone()
	for key in _view.keys: key.disabled = not can_phone or _call_session.state == "connected"
	_view.dial_button.disabled = not can_phone or _call_session.state == "connected"
	_view.pickup_button.disabled = not can_phone or _call_session.state not in ["dial_ready","incoming"]
	_view.hangup_button.disabled = not can_phone or _call_session.state not in ["dial_ready","connected","incoming"]
	for index in _view.reply_buttons.size():
		var button := _view.reply_buttons[index]
		button.visible = index < (_call_session.starter_options.size() if _starter_call() else REPLIES.size())
		button.text = DeskLocalization.text(str(_call_session.starter_options[index].title) if _starter_call() else (str(REPLIES[index]) if index < REPLIES.size() else ""))
		button.disabled = not can_phone or _call_session.state != "connected" or not _call_session.pending_starter_id.is_empty()
	_view.contact_list.mouse_filter = Control.MOUSE_FILTER_STOP if can_phone else Control.MOUSE_FILTER_IGNORE
	_view.identity_label.text = "%s / %s" % [DeskLocalization.text(str(_call_session.selected_contact.get("name","67"))),DeskLocalization.text(str(_call_session.selected_contact.get("identity","助手 / 等待拨号")))]
	_view.portrait.visible = _view.portrait.texture != null and (_call_session.selected_contact.is_empty() or _call_session.dialed_number == "67#")
	_view.player_portrait.visible = _view.player_portrait.texture != null
	_view.player_fallback.visible = _view.player_portrait.texture == null
	_view.player_line.text = _reply_display_text()
	_view.conversation.text = _npc_display_text()
	_layout_scene()
	details_changed.emit(component_details(_focus_mode))


func _layout_scene() -> void:
	if not _built: return
	_update_paper_contents(_focus_mode in ["paper", "archive"] and _focus_progress > .5)
	var geometry: Dictionary = _view.layout_station({
		"size":size, "machine_rect":_machine_rect, "bound_machine":_bound_machine,
		"fixed_desktop":_fixed_desktop_mode, "focus_mode":_focus_mode, "focus_progress":_focus_progress,
		"feed_progress":_output.feed_progress, "continuous_output":_output.continuous_output, "external_details":_external_details,
		"focused":_focused, "has_active_event":not _output.active_event.is_empty(), "has_archive":not _archived_event.is_empty(),
		"starter_call":_starter_call()}, _mouth_geometry)
	_paper_height = geometry.paper_height
	_seal_radius = geometry.seal_radius
	_seal_center = geometry.seal_center
	_paper_polygon = geometry.paper_polygon
	_sync_reward_slips()
	_output.sync_current_page()


func _mouth_geometry() -> Dictionary:
	var page: Node = self
	while page != null and not page.has_meta("studio3d"):
		page = page.get_parent()
	if page != null:
		var mouth: Dictionary = page.get_meta("studio3d").paper_exit("fax_machine")
		return {"origin":get_global_transform().affine_inverse()*mouth.origin,"width":mouth.width,"angle":mouth.angle}
	var machine: TextureRect = _view.display if not _fixed_desktop_mode and _focus_mode == "phone" and (_focused or _focus_progress > 0.0) else _bound_machine
	if is_instance_valid(machine):
		var content := StationView.content_rect(machine)
		var dimensions := machine.texture.get_size() if machine.texture != null else Vector2(1200, 900)
		var mouth := _source_mouth if _source_mouth.has_area() else Rect2(dimensions.x * 0.23, dimensions.y * 0.82, dimensions.x * 0.54, 2)
		var left := content.position + Vector2(mouth.position.x, mouth.end.y) * content.size / dimensions
		var right := content.position + Vector2(mouth.end.x, mouth.end.y) * content.size / dimensions
		var transform := get_global_transform_with_canvas().affine_inverse() * machine.get_global_transform_with_canvas()
		var a := transform * left
		var b := transform * right
		return {"origin":a, "width":a.distance_to(b), "angle":(b - a).angle()}
	return {"origin":_machine_rect.position - global_position + _machine_rect.size * Vector2(0.23, 0.82), "width":_machine_rect.size.x * 0.54, "angle":0.0}


func _machine_polygon() -> PackedVector2Array:
	if is_instance_valid(_bound_machine): return StationView.global_polygon(_bound_machine, StationView.content_rect(_bound_machine))
	return PackedVector2Array([_machine_rect.position, _machine_rect.position + Vector2(_machine_rect.size.x, 0), _machine_rect.end, _machine_rect.position + Vector2(0, _machine_rect.size.y)])


func _paper_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if stamp_at(get_global_mouse_position()): _view.sheet.accept_event()


func _tween_focus(target: float) -> void:
	if _focus_tween != null and _focus_tween.is_valid(): _focus_tween.kill()
	_focus_tween = create_tween()
	_focus_tween.tween_property(self,"_focus_progress",target,_duration(focus_duration,0.22)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_callback(func() -> void:
		if not _focused:
			_restore_machine()
			_focus_mode = ""
		_refresh())
	if _blocked:
		_focus_tween.pause()
		_paused_tweens.append(_focus_tween)


func _restore_machine() -> void:
	if _machine_hidden and is_instance_valid(_bound_machine): _bound_machine.visible = _bound_visible
	_machine_hidden = false


func _duration(value: float, fallback: float) -> float:
	return clampf(value, 0.01, 10.0) if is_finite(value) and value > 0.0 else fallback


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _built:
		refresh_locale.call_deferred()

func refresh_locale() -> void:
	if not _built: return
	_refresh_contacts()
	if not _output.active_event.is_empty() or not _archived_event.is_empty(): _update_paper_contents(_view.body.scroll_active)
	_output.refresh_page_content()
	_view.seal_guide.queue_redraw()
	_refresh()

func _npc_source_text() -> String:
	var source := "等待本地接线。"
	for record: Dictionary in _call_session.call_log:
		if str(record.kind) in ["connected","no_answer","starter_confirmed"]: source = str(record.text)
	if _starter_call() and _call_session.starter_id.is_empty():
		source = "先挑一份起始模因。不是替你写完，只给你一个能继续改的开头。"
		for option: Dictionary in _call_session.starter_options:
			var values := PackedStringArray()
			for value: Variant in (option.get("slots",{}) as Dictionary).values(): values.append(str(value))
			source += "\n"+str(option.title)+"："+" / ".join(values)
	return source

func _npc_display_text() -> String:
	if not (_starter_call() and _call_session.starter_id.is_empty()): return _localized_block(_npc_source_text())
	var displayed := DeskLocalization.text("先挑一份起始模因。不是替你写完，只给你一个能继续改的开头。")
	for option: Dictionary in _call_session.starter_options:
		var values := PackedStringArray()
		for value: Variant in (option.get("slots",{}) as Dictionary).values(): values.append(DeskLocalization.text(str(value)))
		displayed += "\n"+DeskLocalization.text(str(option.title))+": "+" / ".join(values)
	return displayed

func _reply_display_text() -> String:
	if _call_session.selected_reply.is_empty(): return DeskLocalization.text("尚未选择回应。")
	if _call_session.selected_reply.begins_with("选择："):
		for option: Dictionary in _call_session.starter_options:
			if "选择："+str(option.title) == _call_session.selected_reply: return DeskLocalization.text("选择：")+DeskLocalization.text(str(option.title))
	return DeskLocalization.text(_call_session.selected_reply)

func _localized_block(source: String) -> String:
	var exact := str(TranslationServer.translate(StringName(source)))
	if exact != source: return exact
	return "\n".join(DeskLocalization.lines(Array(source.split("\n",true))))

func _refresh_call_view() -> void:
	_diagnostic = _call_session.diagnostic
	_refresh()

func _on_startup_finished(preset_id: String) -> void:
	_refresh_call_view()
	startup_finished.emit(preset_id)

func screen_source() -> Control:
	return _view.number_label

func action_target(action: String) -> Button:
	match action:
		"pickup": return _view.pickup_button
		"dial": return _view.dial_button
		"hangup": return _view.hangup_button
	for button: Button in _view.keys:
		if str(button.get_meta("physical_action", "")) == action or button.text == action: return button
	return null

func call_connected() -> bool:
	return _call_session.state == "connected"

func output_papers() -> Array[Control]:
	return _output.all_pages()

func material_faces() -> Array[Dictionary]:
	var faces: Array[Dictionary] = []
	for key: String in _reward_slips:
		var slip: Control = _reward_slips[key]
		faces.append({"source":slip._face, "key":"fax/" + key, "owner":slip, "visible":slip.is_visible_in_tree()})
	return faces

func cancel_material_drag() -> void:
	for slip in _reward_slips.values(): slip.cancel_drag()

func use_physical_hardware() -> void:
	_view.display.self_modulate.a = 0.0
	_view.phone.modulate.a = 1.0
	_view.number_label.add_theme_color_override("font_color", Color("14271d"))
	for button in _view.keys + [_view.dial_button, _view.pickup_button, _view.hangup_button]: button.modulate.a = 0.0

func _on_output_state_changed() -> void:
	if _output.event_state == "feeding":
		_view.seal.hide()
		_view.seal_text.hide()
	if _output.active_event.is_empty() and _focused and _focus_mode == "paper": close_focus()
	_refresh()

func contacts_snapshot() -> Array[Dictionary]:
	return _call_session.contacts.duplicate(true)

func has_unread_event() -> bool:
	return not _output.active_event.is_empty()

func interaction_focused() -> bool:
	return _focused

func history_focus_page() -> Control:
	var instance_id := str(_camera_pending_archive.get("instance_id", history_details().get("instance_id", "")))
	return _output.page_for_event(instance_id)

func material_slips() -> Array[Control]:
	var slips: Array[Control] = []
	for slip: Control in _reward_slips.values(): slips.append(slip)
	return slips
