class_name DeskFaxStation
extends Control

signal read_completed(instance_id: String)
signal focus_changed(focused: bool)
signal call_changed(record: Dictionary)
signal starter_selected(preset_id: String)
signal startup_finished(preset_id: String)
signal material_requested(record: Dictionary, point: Vector2)

const RewardSlip := preload("res://scripts/demo/desk_event_material_slip.gd")

const A4_RATIO: float = 297.0 / 210.0
const KEY_ZONES := [Rect2(800,536,52,50),Rect2(871,536,52,50),Rect2(943,536,52,50),Rect2(800,600,52,50),Rect2(871,600,52,50),Rect2(943,600,52,50),Rect2(800,665,52,50),Rect2(871,665,52,50),Rect2(943,665,52,50),Rect2(800,729,52,52),Rect2(871,729,52,52),Rect2(943,729,52,52)]
const REPLIES := ["请指出这份消息漏掉的条件。", "先记录，不替我下结论。"]

class SealGuide extends Control:
	func _draw() -> void:
		var centre := size * 0.5
		var radius := minf(size.x,size.y) * 0.5 - 1.0
		for index in range(0,64,2):
			var a := float(index) * TAU / 64.0
			var b := float(index+1) * TAU / 64.0
			draw_line(centre+Vector2(cos(a),sin(a))*radius,centre+Vector2(cos(b),sin(b))*radius,Color("8b8878"),1.2,true)
		var font := get_theme_font("font","Label")
		var fs := 10 if radius < 22 else 12
		var text := "收阅"
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		draw_string(font,centre+Vector2(-width*0.5,font.get_ascent(fs)*0.35),text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color("696b5b"))

class AuthorPortrait extends Control:
	func _draw() -> void:
		var ink := Color("a4c79e")
		draw_rect(Rect2(Vector2.ZERO,size),Color("18281f"))
		draw_circle(Vector2(size.x*0.5,size.y*0.33),size.x*0.16,ink)
		draw_polygon(PackedVector2Array([Vector2(size.x*.21,size.y*.82),Vector2(size.x*.35,size.y*.55),Vector2(size.x*.65,size.y*.55),Vector2(size.x*.79,size.y*.82)]),PackedColorArray([ink]))

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
var _queue: Array[Dictionary] = []
var _active: Dictionary = {}
var _known: Dictionary = {}
var _completed := PackedStringArray()
var _contacts: Array[Dictionary] = []
var _call_log: Array[Dictionary] = []
var _last_read: Dictionary = {}
var _archived_event: Dictionary = {}
var _event_state: String = "idle"
var _call_state: String = "idle"
var _number: String = "67#"
var _diagnostic: String = "仅本地接线，不拨打真实电话。"
var _selected_contact: Dictionary = {}
var _focused: bool = false
var _focus_mode: String = ""
var _blocked: bool = false
var _stamp_armed: bool = false
var _dispatching: bool = false
var _built: bool = false
var _feed_tween: Tween
var _focus_tween: Tween
var _paused_tweens: Array[Tween] = []
var _feed_value: float = 0.0:
	set(value):
		_feed_value = clampf(value, 0.0, 1.0)
		if _built: _layout_scene()
var _focus_mix: float = 0.0:
	set(value):
		_focus_mix = clampf(value, 0.0, 1.0)
		if _built: _layout_scene()
var _shade: ColorRect
var _display: TextureRect
var _sheet: Control
var _paper_shadow: Panel
var _paper: Panel
var _body: RichTextLabel
var _paper_title: Label
var _paper_meta: Label
var _paper_rule: ColorRect
var _paper_text: String = ""
var _seal_guide: Control
var _seal_center := Vector2.ZERO
var _seal_radius: float = 18.0
var _seal: TextureRect
var _seal_text: Label
var _book: Panel
var _book_art: TextureRect
var _ruled_contacts: Control
var _book_heading: Label
var _contact_list: ItemList
var _phone: Control
var _number_label: Label
var _status: Label
var _dial_button: Button
var _pickup_button: Button
var _hangup_button: Button
var _stamp_button: Button
var _stamp_art: TextureRect
var _identity: Panel
var _portrait: TextureRect
var _identity_label: Label
var _conversation: RichTextLabel
var _player_portrait: TextureRect
var _player_fallback: Control
var _player_title: Label
var _player_line: Label
var _reply_buttons: Array[Button] = []
var _selected_reply: String = ""
var _starter_options: Array[Dictionary] = []
var _starter_id: String = ""
var _pending_starter_id: String = ""
var _startup_done: bool = false
var _close_button: Button
var _keys: Array[Button] = []
var _paper_height: float = 160.0
var _paper_polygon := PackedVector2Array()
var _reward_rows: Array[Dictionary] = []
var _reward_slips: Dictionary = {}
var _reward_tray: Control
var _requesting_slip: Control
var _page_keyboard_shortcuts := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	if _contacts.is_empty(): set_contacts([])
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
	_display.texture = _textures.get("machine") as Texture2D
	_portrait.texture = _textures.get("portrait_67") as Texture2D
	_player_portrait.texture = _textures.get("portrait_player") as Texture2D
	_seal.texture = _textures.get("stamp") as Texture2D
	_book_art.texture = _textures.get("phonebook") as Texture2D
	_stamp_art.texture = _textures.get("stamp_prop") as Texture2D
	if _book_art.texture != null:
		_book.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_contact_list.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_contact_list.add_theme_color_override("font_color", Color("252a23"))
	if options.get("source_mouth") is Rect2: _source_mouth = options.source_mouth
	_layout_scene()


func bind_machine(machine: TextureRect, source_mouth: Rect2 = Rect2()) -> void:
	_build()
	_restore_machine()
	_bound_machine = machine
	if machine != null:
		_bound_visible = machine.visible
		_display.texture = machine.texture
		_machine_rect = machine.get_global_rect()
		if _focused and _focus_mode == "phone":
			machine.hide()
			_machine_hidden = true
	if source_mouth.has_area(): _source_mouth = source_mouth
	_layout_scene()


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
	var id := str(event.get("instance_id", "")).strip_edges()
	if id.is_empty() or not event.get("title") is String or not event.get("narrative") is String:
		_diagnostic = "情报缺少 instance_id、标题或正文。"
		_refresh()
		return false
	if bool(event.get("acknowledged", false)) or _known.has(id): return false
	if _focus_mode == "archive": close_focus()
	if event.get("contacts") is Array:
		for contact in event.contacts:
			if contact is Dictionary: add_contact(contact)
	if event.get("contact") is Dictionary: add_contact(event.contact)
	_known[id] = true
	_queue.append(event.duplicate(true))
	if _active.is_empty() and not _dispatching: _start_next()
	return true


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
	if not _built or _reward_tray == null: return
	var wanted := {}
	var active_index := 0
	var tray_index := 0
	var active_id := str(_active.get("instance_id", ""))
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
			(_sheet if current else _reward_tray).add_child(slip)
			slip.configure(row, self, theme)
			slip.dropped.connect(_request_material)
			_reward_slips[key] = slip
		if not slip.is_dragging():
			var host := _sheet if current else _reward_tray
			if slip.get_parent() != host: slip.reparent(host, false)
			slip.rotation = 0.0
			if current:
				var width := maxf(34.0,minf(82.0,(_sheet.size.x-_seal_radius*2-34.0)/maxi(1,_active_reward_count())))
				slip.size = Vector2(width,44.0 if _sheet.size.x > 250 else 36.0)
				slip.position = Vector2(9.0+active_index*(width+3.0),_seal_center.y-slip.size.y*.5+_sheet.size.y-_paper_height)
				active_index += 1
			else:
				slip.size = Vector2(82,52)
				slip.position = Vector2((tray_index%2)*86,(tray_index/2)*20)
				slip.rotation = deg_to_rad(float((tray_index%3)-1)*2.0)
				tray_index += 1
		slip.visible = _focus_mode != "archive" and (not current or _event_state == "ready")
		slip.set_interaction_enabled(slip.visible and not _blocked and _focus_mode != "phone" and _event_state != "retracting")
	_reward_tray.visible = tray_index > 0 and _focus_mode not in ["archive", "phone"]
	_reward_tray.size.y = maxf(52.0,ceilf(float(tray_index)/2.0)*20.0+32.0)
	for key in _reward_slips.keys():
		if not wanted.has(key):
			_reward_slips[key].queue_free()
			_reward_slips.erase(key)

func _active_reward_count() -> int:
	var count := 0
	for row: Dictionary in _reward_rows:
		if str(row.get("instance_id", "")) == str(_active.get("instance_id", "")) and not row.get("requested", false): count += 1
	return count

func _request_material(record: Dictionary, point: Vector2) -> void:
	var local := get_global_transform_with_canvas().affine_inverse()*point
	if _blocked or _focus_mode == "archive" or not Rect2(Vector2.ZERO,size).has_point(local) or Geometry2D.is_point_in_polygon(point,_paper_polygon):
		confirm_material_request(record, false)
		return
	_requesting_slip = _reward_slips.get(_reward_key(record))
	material_requested.emit(record.duplicate(true), point)
	_requesting_slip = null


func offer_starters(options: Array, selected_id: String = "") -> bool:
	_build()
	if _contacts.is_empty(): set_contacts([])
	if options.size() != 3 or not _active.is_empty() or not _queue.is_empty(): return false
	var choices: Array[Dictionary] = []
	var ids: Array[String] = []
	for option in options:
		if not option is Dictionary or not option.get("id") is String or not option.get("title") is String: return false
		var id := str(option.id).strip_edges()
		if id.is_empty() or str(option.title).strip_edges().is_empty() or id in ids: return false
		ids.append(id)
		choices.append(option.duplicate(true))
	if not selected_id.is_empty() and selected_id not in ids: return false
	_starter_options = choices
	_starter_id = selected_id
	_pending_starter_id = ""
	_startup_done = false
	_selected_reply = ""
	_number = "67#"
	_selected_contact = _contacts[0].duplicate(true)
	_call_state = "incoming"
	_diagnostic = "67 来电。拿起听筒，听完三份起始模因再作选择。"
	focus()
	_refresh()
	return true


func confirm_starter(preset_id: String) -> bool:
	if not _starter_call() or preset_id != _pending_starter_id: return false
	_starter_id = preset_id
	_pending_starter_id = ""
	for option in _starter_options:
		if str(option.id) == preset_id: _selected_reply = "选择：" + str(option.title)
	_append_call("starter_confirmed", "选好了。放回听筒后，到稿纸上编辑、培养，再决定怎样传播。")
	_refresh()
	return true


func reject_starter(message: String) -> void:
	_pending_starter_id = ""
	_diagnostic = message
	_refresh()


func clear_starter_offer() -> void:
	for slip in _reward_slips.values(): slip.queue_free()
	_reward_slips.clear()
	_reward_rows.clear()
	_starter_options.clear()
	_starter_id = ""
	_pending_starter_id = ""
	_startup_done = false
	_refresh()


func _starter_call() -> bool:
	return _can_phone() and _call_state == "connected" and _number == "67#" and not _startup_done and not _starter_options.is_empty()


func view_archived_event(event: Dictionary) -> bool:
	_build()
	if _blocked: return false
	if not _active.is_empty() or not _queue.is_empty() or _dispatching:
		_diagnostic = "先处理当前待阅情报，再翻历史档案。"
		if _event_state == "ready": focus_paper()
		else: _refresh()
		return false
	if str(event.get("instance_id","")).strip_edges().is_empty() or not event.get("title") is String or not event.get("narrative") is String:
		_diagnostic = "历史记录缺少真实编号、标题或正文。"
		_refresh()
		return false
	var was_focused := _focused
	_archived_event = event.duplicate(true)
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
	var was_focused := _focused
	_archived_event = {}
	_focused = true
	_focus_mode = "phone"
	if is_instance_valid(_bound_machine):
		if not _machine_hidden: _bound_visible = _bound_machine.visible
		_bound_machine.hide()
		_machine_hidden = true
	_tween_focus(1.0)
	_refresh()
	if not was_focused: focus_changed.emit(true)
	return true


func focus_paper() -> bool:
	if _blocked or _event_state != "ready" or _active.is_empty() or (_focused and _focus_mode == "paper"): return false
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
		_archived_event = {}
		_focus_mode = ""
		if _focus_tween != null and _focus_tween.is_valid(): _focus_tween.kill()
		_focus_mix = 0.0
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
	if blocked:
		for tween in [_feed_tween,_focus_tween]:
			if tween != null and tween.is_valid() and tween.is_running():
				tween.pause()
				_paused_tweens.append(tween)
	else:
		for tween in _paused_tweens:
			if tween != null and tween.is_valid(): tween.play()
		_paused_tweens.clear()
	_stamp_armed = false if blocked else _stamp_armed
	if not blocked and _event_state == "retracting" and _feed_value == 0.0: _finish_read.call_deferred()
	_refresh()


func stamp() -> bool:
	if _blocked or _focus_mode == "archive" or (_focused and _focus_mode == "phone") or _event_state != "ready" or _active.is_empty(): return false
	_event_state = "retracting"
	_stamp_armed = false
	_seal.visible = _seal.texture != null
	_seal_text.visible = _seal.texture == null
	_refresh()
	_kill_feed_tween()
	_feed_tween = create_tween()
	_feed_tween.tween_property(self, "_feed_value", 0.0, _duration(retract_duration, 0.55)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_feed_tween.tween_callback(_finish_read)
	if _blocked:
		_feed_tween.pause()
		_paused_tweens.append(_feed_tween)
	return true


func arm_stamp() -> bool:
	if _blocked or _focus_mode == "archive" or (_focused and _focus_mode == "phone") or _event_state != "ready" or _active.is_empty(): return false
	_stamp_armed = true
	_diagnostic = "印章已拿取；对准纸张右下的收阅圆框。"
	_refresh()
	return true


func stamp_at(global_position: Vector2) -> bool:
	if not is_finite(global_position.x) or not is_finite(global_position.y): return false
	var local := _sheet.get_global_transform_with_canvas().affine_inverse() * global_position
	if local.distance_to(_seal_center) > _seal_radius: return false
	return stamp()


func set_contacts(contacts: Array) -> void:
	_contacts.clear()
	_contacts.append({"number":"67#", "name":"67", "identity":"你的助手 / 情报收集与传播观察", "greeting":"线路是通的。消息是否值得转发，是另一笔账。"})
	for contact in contacts:
		if contact is Dictionary: add_contact(contact)
	_refresh_contacts()


func add_contact(contact: Dictionary) -> bool:
	var number := str(contact.get("number", "")).strip_edges()
	if not _valid_number(number) or str(contact.get("name", "")).strip_edges().is_empty(): return false
	for known in _contacts:
		if str(known.number) == number: return false
	_contacts.append({"number":number, "name":str(contact.name), "identity":str(contact.get("identity", "已收录联系人")), "greeting":str(contact.get("greeting", "线路接通。对方没有补充消息。"))})
	_refresh_contacts()
	return true


func keypad_key(key: String) -> bool:
	if key in ["call", "dial"]: return dial()
	if key == "pickup": return pickup()
	if key == "hangup": return hangup()
	if not _can_phone() or _call_state == "connected": return false
	if key == "backspace":
		_number = _number.left(maxi(0, _number.length() - 1))
	elif key == "clear":
		_number = ""
	elif key.length() == 1 and (key in "0123456789#"):
		if _number.length() >= 12: return false
		_number += key
	else:
		return false
	_call_state = "idle"
	_selected_contact = {}
	_diagnostic = "号码只在本地电话簿中匹配。"
	_refresh()
	return true


func dial() -> bool:
	if not _can_phone() or _call_state == "connected": return false
	_selected_contact = {}
	if _valid_number(_number):
		for contact in _contacts:
			if str(contact.number) == _number: _selected_contact = contact.duplicate(true)
	if _selected_contact.is_empty():
		_call_state = "invalid"
		_diagnostic = "无人应答：号码未收录或格式无效。"
		_append_call("no_answer", "电话簿没有这个号码。空号不会因为你多拨一次就升职。")
		_refresh()
		return false
	_call_state = "dial_ready"
	_diagnostic = "已找到 %s；拿起听筒接线。" % str(_selected_contact.name)
	_refresh()
	return true


func pickup() -> bool:
	if not _can_phone() or _call_state not in ["dial_ready", "incoming"] or _selected_contact.is_empty(): return false
	_call_state = "connected"
	var line := str(_selected_contact.greeting)
	if _number == "67#" and not str(_last_read.get("mentor_comment", "")).strip_edges().is_empty(): line = str(_last_read.mentor_comment)
	_diagnostic = "本地接线 / %s" % str(_selected_contact.name)
	_append_call("connected", line)
	_refresh()
	return true


func hangup() -> bool:
	if _blocked or not _focused or _focus_mode != "phone" or _call_state not in ["connected", "dial_ready", "incoming"]: return false
	var finish_startup := _starter_call() and not _starter_id.is_empty()
	_append_call("hangup", "接线结束。事实留在纸上，不占用听筒。")
	_call_state = "idle"
	_selected_contact = {}
	_diagnostic = "听筒已放回。"
	_refresh()
	if finish_startup:
		_startup_done = true
		startup_finished.emit(_starter_id)
	return true


func choose_response(index: int) -> bool:
	if _starter_call():
		if index < 0 or index >= _starter_options.size() or not _pending_starter_id.is_empty(): return false
		_pending_starter_id = str(_starter_options[index].id)
		starter_selected.emit(_pending_starter_id)
		return true
	if not _can_phone() or _call_state != "connected" or index < 0 or index >= REPLIES.size(): return false
	_selected_reply = str(REPLIES[index])
	_append_call("player_option",_selected_reply)
	_refresh()
	return true


func reset_station() -> void:
	_kill_feed_tween()
	if _focus_tween != null and _focus_tween.is_valid(): _focus_tween.kill()
	_paused_tweens.clear()
	var was_focused := _focused
	_focused = false
	_focus_mode = ""
	_focus_mix = 0.0
	_restore_machine()
	_queue.clear()
	_active.clear()
	_known.clear()
	_completed.clear()
	_last_read.clear()
	_archived_event = {}
	_paper_text = ""
	_selected_reply = ""
	for slip in _reward_slips.values(): slip.queue_free()
	_reward_slips.clear()
	_reward_rows.clear()
	_starter_options.clear()
	_starter_id = ""
	_pending_starter_id = ""
	_startup_done = false
	_call_log.clear()
	_event_state = "idle"
	_feed_value = 0.0
	_stamp_armed = false
	_call_state = "idle"
	_selected_contact.clear()
	_number = "67#"
	_diagnostic = "情报收件箱已重同步。"
	set_contacts([])
	_refresh()
	if was_focused: focus_changed.emit(false)


func inspection() -> Dictionary:
	var seal_global := _sheet.get_global_transform_with_canvas()*_seal_center if _built else Vector2.ZERO
	var key_points: Dictionary = {}
	var key_rects: Dictionary = {}
	if _built:
		for control in _keys+[_dial_button,_pickup_button,_hangup_button]:
			key_points[str(control.name)] = control.get_global_transform_with_canvas()*(control.size*.5)
			key_rects[str(control.name)] = control.get_global_rect()
	return {
		"event_state":_event_state,"active_event":_active.duplicate(true),"queue":_queue.duplicate(true),"completed":_completed.duplicate(),
		"feed_progress":_feed_value,"focused":_focused,"focus_mode":_focus_mode,"focus_progress":_focus_mix,"blocked":_blocked,
		"stamp_armed":_stamp_armed,"busy":_event_state in ["feeding","retracting"],
		"paper_rect":_sheet.get_global_rect() if _built else Rect2(),"paper_full_size":Vector2(_sheet.size.x,_paper_height) if _built else Vector2.ZERO,
		"paper_visible":_sheet.visible if _built else false,"paper_polygon":_paper_polygon.duplicate(),"paper_rotation":_sheet.rotation if _built else 0.0,
		"paper_text":_paper_text,"rendered_paper_text":(_paper_meta.text+"\n" if _paper_meta.visible else "")+_paper_title.text+"\n\n"+_body.text if _built else "","paper_view":"archive" if _focus_mode == "archive" else ("full" if _focus_mode == "paper" and _focus_mix > .5 else "compact"),"read_only":_focus_mode == "archive","archived_event":_archived_event.duplicate(true),"paper_scroll_active":_body.scroll_active if _built else false,"paper_border_widths":[(_paper.get_theme_stylebox("panel") as StyleBoxFlat).get_border_width(SIDE_LEFT),(_paper.get_theme_stylebox("panel") as StyleBoxFlat).get_border_width(SIDE_TOP),(_paper.get_theme_stylebox("panel") as StyleBoxFlat).get_border_width(SIDE_RIGHT),(_paper.get_theme_stylebox("panel") as StyleBoxFlat).get_border_width(SIDE_BOTTOM)] if _built else [],"paper_shadow_visible":_paper_shadow.visible if _built else false,"paper_shadow_size":(_paper_shadow.get_theme_stylebox("panel") as StyleBoxFlat).shadow_size if _built else 0,"seal_center":seal_global,"seal_radius":_seal_radius,"seal_rect":Rect2(seal_global-Vector2.ONE*_seal_radius,Vector2.ONE*_seal_radius*2),
		"reward_slips":_reward_slips.values().map(func(slip): return slip.inspection()),"reward_rows":_reward_rows.duplicate(true),
		"source_mouth":_source_mouth,"source_key_zones":KEY_ZONES,"keyboard_points":key_points,"keyboard_rects":key_rects,
		"machine_rect":_machine_rect,"viewport_rect":_viewport_rect,"call_state":_call_state,"number":_number,"diagnostic":_diagnostic,
		"contacts":_contacts.duplicate(true),"call_log":_call_log.duplicate(true),"last_read":_last_read.duplicate(true),
		"pickup_enabled":not _pickup_button.disabled if _built else false,"npc_text":_conversation.text if _built else "","player_text":_selected_reply,"dialogue_options":_starter_options.duplicate(true) if _starter_call() else REPLIES,
		"starter_options":_starter_options.duplicate(true),"starter_id":_starter_id,"pending_starter_id":_pending_starter_id,"startup_done":_startup_done,
		"dialogue_rect":_identity.get_global_rect() if _built else Rect2(),"npc_rect":_conversation.get_global_rect() if _built else Rect2(),"player_rect":_player_line.get_global_rect() if _built else Rect2(),
		"portrait_67_bound":_portrait.texture != null if _built else false,"player_portrait_native":_player_portrait.texture == null if _built else false,
		"network_calls":0,"economic_calls":0,"mouse_filter":mouse_filter,"focus_shade_visible":_shade.visible if _built else false,
		"nodes":{"sheet":str(_sheet.get_path()) if _built else "","keypad":str(_phone.get_path()) if _built else "","book":str(_book.get_path()) if _built else "","identity":str(_identity.get_path()) if _built else "","seal":str(_seal_guide.get_path()) if _built else ""}}


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
	if _page_keyboard_shortcuts and event is InputEventKey:
		var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		# The integrated page owns these shortcuts even during a focused call.
		if key == KEY_ESCAPE or (key == KEY_D and event.ctrl_pressed): return
	if event is InputEventMouseButton:
		for slip in _reward_slips.values():
			if slip.visible and Rect2(Vector2.ZERO,slip.size).has_point(slip.get_global_transform_with_canvas().affine_inverse()*event.position): return
	if event is InputEventKey and handle_key(event):
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _can_phone() and _book.visible:
			var point: Vector2 = _ruled_contacts.get_global_transform_with_canvas().affine_inverse()*event.position
			for row: Dictionary in _ruled_contacts.inspection().rows:
				var area := Rect2(row.name_baseline-Vector2(4,12),Vector2(_ruled_contacts.size.x*.7,14))
				if area.has_point(point):
					_select_contact(int(row.index))
					get_viewport().set_input_as_handled()
					return
		if (_stamp_armed or _focus_mode == "paper" or not _focused) and stamp_at(event.position):
			get_viewport().set_input_as_handled()
			return
		if not _focused and _event_state == "ready" and Geometry2D.is_point_in_polygon(event.position,_paper_polygon):
			if focus_paper(): get_viewport().set_input_as_handled()
		elif not _focused and Geometry2D.is_point_in_polygon(event.position, _machine_polygon()):
			if focus(): get_viewport().set_input_as_handled()


func _build() -> void:
	if _built: return
	_built = true
	_shade = ColorRect.new()
	_shade.name = "FocusShade"
	_shade.color = Color(0.12,0.13,0.12,0.68)
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_display = _image("FocusedMachine",self)
	_paper_shadow = Panel.new()
	_paper_shadow.name = "PaperShadow"
	_paper_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color.TRANSPARENT
	shadow.shadow_color = Color(0,0,0,.22)
	shadow.shadow_size = 4
	shadow.shadow_offset = Vector2(2,3)
	_paper_shadow.add_theme_stylebox_override("panel",shadow)
	add_child(_paper_shadow)
	_sheet = Control.new()
	_sheet.name = "EventSheet"
	_sheet.clip_contents = true
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sheet)
	_paper = _panel("PaperSurface",_sheet,Color("e7e0c9"))
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper_style := _paper.get_theme_stylebox("panel") as StyleBoxFlat
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: paper_style.set_border_width(side,0)
	_paper_meta = _label("SourceLine","",_sheet,11)
	_paper_meta.add_theme_color_override("font_color",Color("777766"))
	_paper_title = _label("Headline","",_sheet,22)
	_paper_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_paper_rule = ColorRect.new()
	_paper_rule.name = "PrintRule"
	_paper_rule.color = Color("6a6d5c")
	_paper_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(_paper_rule)
	_body = RichTextLabel.new()
	_body.name = "Intelligence"
	_body.bbcode_enabled = false
	_body.scroll_active = true
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_color_override("default_color",Color("292c26"))
	_sheet.add_child(_body)
	_seal_guide = SealGuide.new()
	_seal_guide.name = "SealGuide"
	_seal_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(_seal_guide)
	_reward_tray = Control.new()
	_reward_tray.name = "UncollectedRewardSlips"
	_reward_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_reward_tray)
	_seal = _image("ReceivedSeal",_sheet)
	_seal_text = _label("ReceivedSealFallback","已收阅",_sheet,18)
	_seal_text.add_theme_color_override("font_color",Color("8c3029"))
	_book = _panel("TelephoneBook",self,Color("c4bda8"))
	_book_art = _image("BookAsset",_book)
	_ruled_contacts = preload("res://scripts/demo/desk_ruled_contacts.gd").new()
	_ruled_contacts.name = "RuledContacts"
	_book.add_child(_ruled_contacts)
	_book_heading = _label("BookHeading","电话簿 / 已收录",_book,14)
	_contact_list = ItemList.new()
	_contact_list.name = "Contacts"
	_contact_list.item_selected.connect(_select_contact)
	_book.add_child(_contact_list)
	_phone = Control.new()
	_phone.name = "Keypad"
	_phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phone)
	_number_label = _label("Number",_number,_phone,14)
	_number_label.add_theme_color_override("font_color",Color("bcdf9e"))
	for index in 12:
		var key: String = ["1","2","3","4","5","6","7","8","9","#","0","backspace"][index]
		var button := _button("Key"+str(index),"退" if key == "backspace" else key,_phone)
		_flat_key(button)
		button.pressed.connect(func() -> void: keypad_key(key))
		_keys.append(button)
	_dial_button = _button("Dial","拨",_phone)
	_flat_key(_dial_button)
	_dial_button.pressed.connect(dial)
	_pickup_button = _button("Pickup","接",_phone)
	_flat_key(_pickup_button)
	_pickup_button.pressed.connect(pickup)
	_hangup_button = _button("Hangup","挂断",_phone)
	_flat_key(_hangup_button)
	_hangup_button.pressed.connect(hangup)
	_identity = _panel("CallIdentity",self,Color("14271d"))
	_portrait = _image("Portrait67",_identity)
	_identity_label = _label("Identity","67 / 助手",_identity,13)
	_identity_label.add_theme_color_override("font_color",Color("a4c79e"))
	_conversation = RichTextLabel.new()
	_conversation.name = "CallLog"
	_conversation.bbcode_enabled = false
	_conversation.scroll_active = true
	_conversation.add_theme_color_override("default_color",Color("b8d9ac"))
	_conversation.add_theme_font_size_override("normal_font_size",14)
	_identity.add_child(_conversation)
	_player_portrait = _image("PlayerPortrait",_identity)
	_player_fallback = AuthorPortrait.new()
	_player_fallback.name = "AnonymousAuthor"
	_player_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_identity.add_child(_player_fallback)
	_player_title = _label("PlayerIdentity","作者 / 你",_identity,13)
	_player_title.add_theme_color_override("font_color",Color("a4c79e"))
	_player_line = _label("SelectedResponse","尚未选择回应。",_identity,13)
	_player_line.add_theme_color_override("font_color",Color("b8d9ac"))
	_player_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for index in 3:
		var button := _button("Response"+str(index),str(REPLIES[index]) if index < REPLIES.size() else "",_identity)
		button.add_theme_font_size_override("font_size",12)
		button.pressed.connect(func() -> void: choose_response(index))
		_reply_buttons.append(button)
	_status = _label("Diagnostic",_diagnostic,self,12)
	_status.add_theme_color_override("font_color",Color("e5ddc8"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stamp_button = _button("Stamp","拿取印章",self)
	_stamp_button.pressed.connect(arm_stamp)
	_stamp_art = _image("StampToolAsset",self)
	_close_button = _button("CloseFocus","放回桌面",self)
	_close_button.pressed.connect(close_focus)
	_refresh()


func _flat_key(button: Button) -> void:
	button.flat = true
	button.add_theme_font_size_override("font_size",10)
	button.add_theme_color_override("font_color",Color("e4dcc4"))
	for state in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())


func _start_next() -> void:
	if _queue.is_empty():
		_event_state = "idle"
		_refresh()
		return
	_active = _queue.pop_front()
	_event_state = "feeding"
	_feed_value = 0.0
	_seal.hide()
	_seal_text.hide()
	_update_paper_contents(false)
	_refresh()
	_kill_feed_tween()
	_feed_tween = create_tween()
	_feed_tween.tween_property(self,"_feed_value",1.0,_duration(feed_duration,0.65)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_feed_tween.tween_callback(func() -> void: _event_state = "ready"; _refresh())
	if _blocked:
		_feed_tween.pause()
		_paused_tweens.append(_feed_tween)


func _update_paper_contents(expanded: bool) -> void:
	var event: Dictionary = _archived_event if _focus_mode == "archive" else _active
	if event.is_empty():
		_paper_text = ""
		_paper_title.text = ""
		_body.text = ""
		return
	var meta := "情报摘录 / 助手收集  ·  H%s / %s" % [str(event.get("hour","?")),str(event.get("origin","未标出处"))]
	var mentor := str(event.get("mentor_comment","先看清消息的出处，再决定要不要发声。"))
	var full_body := "%s\n\n作用摘录\n%s\n\n实际作用\n%s\n\n67：%s" % [str(event.narrative),str(event.get("impact_text","未提供作用摘要")),str(event.get("effect_text","未提供实际作用记录")),mentor]
	var rewards := str(event.get("reward_text", ""))
	if not rewards.is_empty(): full_body += "\n\n" + rewards
	var rendered := full_body if expanded else "%s\n\n67：%s" % [str(event.narrative),mentor]
	_paper_text = meta+"\n"+str(event.title)+"\n\n"+full_body
	if _paper_meta.text != meta: _paper_meta.text = meta
	if _paper_title.text != str(event.title): _paper_title.text = str(event.title)
	if _body.text != rendered: _body.text = rendered
	_body.scroll_active = expanded
	_paper_meta.visible = expanded
	_paper_rule.visible = expanded


func _finish_read() -> void:
	if _active.is_empty() or _event_state != "retracting" or _blocked: return
	var id := str(_active.instance_id)
	_last_read = _active.duplicate(true)
	_completed.append(id)
	_active = {}
	_event_state = "idle"
	if _focused and _focus_mode == "paper": close_focus()
	_dispatching = true
	_refresh()
	read_completed.emit(id)
	_dispatching = false
	if _active.is_empty(): _start_next()


func _can_phone() -> bool:
	return _focused and _focus_mode == "phone" and not _blocked and _active.is_empty() and _queue.is_empty() and not _dispatching


func _valid_number(number: String) -> bool:
	if number.length() < 2 or number.length() > 12 or not number.ends_with("#"): return false
	for character in number.left(number.length() - 1):
		if character not in "0123456789": return false
	return true


func _append_call(kind: String, text: String) -> void:
	var source_id := str(_last_read.get("instance_id", "")) if _number == "67#" and kind == "connected" else ""
	var record := {"index":_call_log.size(), "number":_number, "name":str(_selected_contact.get("name", "未收录")), "kind":kind, "text":text, "event_id":source_id, "context_event_id":str(_last_read.get("instance_id", "")), "local_only":true}
	_call_log.append(record)
	call_changed.emit(record.duplicate(true))


func _select_contact(index: int) -> void:
	if not _can_phone() or index < 0 or index >= _contacts.size(): return
	_number = str(_contacts[index].number)
	_call_state = "idle"
	_selected_contact = {}
	_diagnostic = "已抄入电话簿号码；拨号后才能拿起听筒。"
	_refresh()


func _refresh_contacts() -> void:
	if not _built: return
	_ruled_contacts.set_contacts(_contacts)
	_contact_list.hide()
	_book_heading.hide()
	_contact_list.clear()
	for contact in _contacts:
		var index := _contact_list.add_item("%s  %s" % [str(contact.number), str(contact.name)])
		_contact_list.set_item_tooltip(index, str(contact.identity))


func _refresh() -> void:
	if not _built: return
	var phone_ui := _focused and _focus_mode == "phone" and not _blocked
	var paper_ui := _focused and _focus_mode in ["paper","archive"] and not _blocked
	_shade.visible = _focused and not _blocked
	for node in [_book,_phone,_identity,_status]: node.visible = phone_ui
	_close_button.visible = _focused and not _blocked
	_stamp_button.hide()
	_stamp_art.hide()
	_display.visible = _focus_mode == "phone" and (_focus_mix > 0.0 or _focused)
	_sheet.visible = ((not _active.is_empty() and _feed_value > 0.0) or (_focused and _focus_mode == "archive" and not _archived_event.is_empty())) and _focus_mode != "phone"
	_paper_shadow.visible = _sheet.visible
	_reward_tray.position = Vector2(clampf(_machine_rect.end.x+10,10,maxf(10,size.x-184)),clampf(_machine_rect.end.y-80,10,maxf(10,size.y-180)))
	_reward_tray.size = Vector2(180,160)
	_sync_reward_slips()
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP if paper_ui else Control.MOUSE_FILTER_IGNORE
	_body.mouse_filter = Control.MOUSE_FILTER_PASS if paper_ui else Control.MOUSE_FILTER_IGNORE
	_number_label.text = _number if not _number.is_empty() else "号码 / #"
	_status.text = _diagnostic
	_stamp_button.disabled = _blocked or _event_state != "ready"
	_seal_guide.visible = _event_state != "retracting" and _focus_mode != "archive"
	if _focus_mode == "archive":
		_seal.hide()
		_seal_text.hide()
	var can_phone := _can_phone()
	for key in _keys: key.disabled = not can_phone or _call_state == "connected"
	_dial_button.disabled = not can_phone or _call_state == "connected"
	_pickup_button.disabled = not can_phone or _call_state not in ["dial_ready","incoming"]
	_hangup_button.disabled = not can_phone or _call_state not in ["dial_ready","connected","incoming"]
	for index in _reply_buttons.size():
		var button := _reply_buttons[index]
		button.visible = index < (_starter_options.size() if _starter_call() else REPLIES.size())
		button.text = str(_starter_options[index].title) if _starter_call() else (str(REPLIES[index]) if index < REPLIES.size() else "")
		button.disabled = not can_phone or _call_state != "connected" or not _pending_starter_id.is_empty()
	_contact_list.mouse_filter = Control.MOUSE_FILTER_STOP if can_phone else Control.MOUSE_FILTER_IGNORE
	_identity_label.text = "%s / %s" % [str(_selected_contact.get("name","67")),str(_selected_contact.get("identity","助手 / 等待拨号"))]
	_portrait.visible = _portrait.texture != null and (_selected_contact.is_empty() or _number == "67#")
	_player_portrait.visible = _player_portrait.texture != null
	_player_fallback.visible = _player_portrait.texture == null
	_player_line.text = _selected_reply if not _selected_reply.is_empty() else "尚未选择回应。"
	var npc_line := "等待本地接线。"
	for record in _call_log:
		if str(record.kind) in ["connected","no_answer","starter_confirmed"]: npc_line = str(record.text)
	if _starter_call() and _starter_id.is_empty():
		npc_line = "先挑一份起始模因。不是替你写完，只给你一个能继续改的开头。"
		for option in _starter_options:
			var expression := PackedStringArray()
			for value in (option.get("slots", {}) as Dictionary).values(): expression.append(str(value))
			npc_line += "\n" + str(option.title) + "：" + " / ".join(expression)
	_conversation.text = npc_line
	_layout_scene()


func _layout_scene() -> void:
	if not _built: return
	_shade.position = Vector2.ZERO
	_shade.size = size
	var target_width := minf(620.0,maxf(300.0,size.x*.48))
	var texture_size := _display.texture.get_size() if _display.texture != null else Vector2(1312,1199)
	var target_height := minf(target_width*texture_size.y/maxf(1.0,texture_size.x),maxf(220.0,size.y-248.0))
	var target := Rect2((size.x-target_width)*.5,18,target_width,target_height)
	var local_base := Rect2(_machine_rect.position-global_position,_machine_rect.size)
	_display.position = local_base.position.lerp(target.position,_focus_mix)
	_display.size = local_base.size.lerp(target.size,_focus_mix)
	var angle := _bound_machine.get_global_transform_with_canvas().get_rotation() if is_instance_valid(_bound_machine) else 0.0
	_display.rotation = lerpf(angle,0.0,_focus_mix)
	var geometry := _mouth_geometry()
	var origin: Vector2 = geometry.origin
	var width: float = geometry.width
	var paper_angle: float = geometry.angle
	if _focus_mode in ["paper","archive"]:
		var height := minf(680.0,maxf(240.0,size.y-64.0))
		var paper_width := minf(height/A4_RATIO,maxf(180.0,size.x-48.0))
		var paper_target := (size-Vector2(paper_width,paper_width*A4_RATIO))*.5
		origin = origin.lerp(paper_target,_focus_mix)
		width = lerpf(width,paper_width,_focus_mix)
		paper_angle = lerpf(paper_angle,0.0,_focus_mix)
	_sheet.position = origin
	_sheet.rotation = paper_angle
	_paper_height = width*A4_RATIO
	var visual_feed := 1.0 if _focus_mode == "archive" else _feed_value
	_sheet.size = Vector2(width,_paper_height*visual_feed)
	_paper_shadow.position = _sheet.position
	_paper_shadow.rotation = _sheet.rotation
	_paper_shadow.size = _sheet.size
	# Keep one A4 sheet moving through the outlet.
	var material_offset := _sheet.size.y-_paper_height
	_paper.position = Vector2(0,material_offset)
	_paper.size = Vector2(width,_paper_height)
	var large := _focus_mode in ["paper","archive"] and _focus_mix > .5
	_update_paper_contents(large)
	var padding := 22.0 if large else 9.0
	_paper_meta.position = Vector2(padding,padding+material_offset)
	_paper_meta.size = Vector2(maxf(0,width-padding*2),16 if large else 12)
	_paper_meta.add_theme_font_size_override("font_size",11 if large else 7)
	_paper_title.position = Vector2(padding,(48 if large else 9)+material_offset)
	_paper_title.size = Vector2(maxf(0,width-padding*2),64 if large else 30)
	_paper_title.add_theme_font_size_override("font_size",23 if large else (11 if width >= 150 else 10))
	var body_y := 127.0 if large else 47.0
	_paper_rule.position = Vector2(padding,body_y-10+material_offset)
	_paper_rule.size = Vector2(maxf(0,width-padding*2),1)
	_body.position = Vector2(padding,body_y+material_offset)
	_body.size = Vector2(maxf(0,width-padding*2),maxf(0,_paper_height-body_y-(92 if large else 48)))
	_body.add_theme_font_size_override("normal_font_size",15 if large else (9 if width >= 150 else 8))
	_seal_radius = 28.0 if large else minf(18.0,width*.1)
	_seal_center = Vector2(width-padding-_seal_radius,_paper_height-padding-_seal_radius)
	_seal_guide.position = _seal_center-Vector2.ONE*_seal_radius+Vector2(0,material_offset)
	_seal_guide.size = Vector2.ONE*_seal_radius*2
	_seal_guide.queue_redraw()
	_seal.position = _seal_guide.position
	_seal.size = _seal_guide.size
	_seal_text.position = _seal_guide.position+Vector2(0,_seal_radius*.6)
	_seal_text.add_theme_font_size_override("font_size",14 if large else 9)
	_paper_polygon = _global_polygon(_sheet,Rect2(Vector2.ZERO,_sheet.size))
	_phone.position = _display.position
	_phone.size = _display.size
	_phone.rotation = _display.rotation
	for index in _keys.size(): _place_source_control(_keys[index],KEY_ZONES[index])
	_place_source_control(_dial_button,Rect2(1068,546,90,48))
	_place_source_control(_pickup_button,Rect2(1068,607,90,51))
	_place_source_control(_hangup_button,Rect2(1068,670,90,106))
	_place_source_control(_number_label,Rect2(374,556,370,82))
	_book.position = Vector2(20,60)
	_book.size = Vector2(250,210)
	_book_art.position = Vector2.ZERO
	_book_art.size = _book.size
	_book_heading.position = Vector2(42,44) if _book_art.texture != null else Vector2(10,10)
	_contact_list.position = Vector2(42,75) if _book_art.texture != null else Vector2(8,40)
	_contact_list.size = Vector2(184,104)
	_ruled_contacts.layout_book(Rect2(Vector2.ZERO,_book.size))
	_contact_list.hide()
	_book_heading.hide()
	var dialogue_width := minf(980.0,maxf(420.0,size.x-36))
	var dialogue_height := 218.0 if _starter_call() else 180.0
	_identity.position = Vector2((size.x-dialogue_width)*.5,maxf(280.0,size.y-dialogue_height-34.0))
	_identity.size = Vector2(dialogue_width,dialogue_height)
	var half := dialogue_width*.5
	_portrait.position = Vector2(16,16)
	_portrait.size = Vector2(70,70)
	_identity_label.position = Vector2(100,14)
	_identity_label.size = Vector2(half-116,38)
	_identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conversation.position = Vector2(100,58)
	_conversation.size = Vector2(half-118,100)
	_player_portrait.position = Vector2(half+14,16)
	_player_portrait.size = Vector2(60,60)
	_player_fallback.position = _player_portrait.position
	_player_fallback.size = _player_portrait.size
	_player_fallback.queue_redraw()
	_player_title.position = Vector2(half+86,14)
	_player_title.size = Vector2(half-102,20)
	_player_line.position = Vector2(half+86,42)
	_player_line.size = Vector2(half-102,36)
	for index in _reply_buttons.size():
		_reply_buttons[index].position = Vector2(half+14,86+index*36)
		_reply_buttons[index].size = Vector2(half-30,30)
	_status.position = Vector2(20,size.y-28)
	_status.size = Vector2(maxf(0,size.x-200),24)
	_close_button.position = Vector2(size.x-154,12)
	_close_button.size = Vector2(138,32)
	_sheet.visible = ((not _active.is_empty() and _feed_value > 0.0) or (_focused and _focus_mode == "archive" and not _archived_event.is_empty())) and _focus_mode != "phone"
	_paper_shadow.visible = _sheet.visible
	_reward_tray.position = Vector2(clampf(_machine_rect.end.x+10,10,maxf(10,size.x-184)),clampf(_machine_rect.end.y-80,10,maxf(10,size.y-180)))
	_reward_tray.size = Vector2(180,160)
	_sync_reward_slips()


func _place_source_control(control: Control, source: Rect2) -> void:
	var content := _content_rect(_display)
	var dimensions := _display.texture.get_size() if _display.texture != null else Vector2(1312,1199)
	control.position = content.position+source.position*content.size/dimensions
	control.size = source.size*content.size/dimensions


func _mouth_geometry() -> Dictionary:
	var machine: TextureRect = _display if _focus_mode == "phone" and (_focused or _focus_mix > 0.0) else _bound_machine
	if is_instance_valid(machine):
		var content := _content_rect(machine)
		var dimensions := machine.texture.get_size() if machine.texture != null else Vector2(1200, 900)
		var mouth := _source_mouth if _source_mouth.has_area() else Rect2(dimensions.x * 0.23, dimensions.y * 0.82, dimensions.x * 0.54, 2)
		var left := content.position + Vector2(mouth.position.x, mouth.end.y) * content.size / dimensions
		var right := content.position + Vector2(mouth.end.x, mouth.end.y) * content.size / dimensions
		var transform := get_global_transform_with_canvas().affine_inverse() * machine.get_global_transform_with_canvas()
		var a := transform * left
		var b := transform * right
		return {"origin":a, "width":a.distance_to(b), "angle":(b - a).angle()}
	return {"origin":_machine_rect.position - global_position + _machine_rect.size * Vector2(0.23, 0.82), "width":_machine_rect.size.x * 0.54, "angle":0.0}


func _content_rect(machine: TextureRect) -> Rect2:
	if machine.texture == null: return Rect2(Vector2.ZERO, machine.size)
	var dimensions := machine.texture.get_size()
	if machine.stretch_mode in [TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED]:
		var scale := minf(machine.size.x / maxf(1, dimensions.x), machine.size.y / maxf(1, dimensions.y))
		var scaled := dimensions * scale
		return Rect2((machine.size - scaled) * 0.5 if machine.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED else Vector2.ZERO, scaled)
	return Rect2(Vector2.ZERO, machine.size)


func _machine_polygon() -> PackedVector2Array:
	if is_instance_valid(_bound_machine): return _global_polygon(_bound_machine, _content_rect(_bound_machine))
	return PackedVector2Array([_machine_rect.position, _machine_rect.position + Vector2(_machine_rect.size.x, 0), _machine_rect.end, _machine_rect.position + Vector2(0, _machine_rect.size.y)])


func _global_polygon(node: Control, rect: Rect2) -> PackedVector2Array:
	var transform := node.get_global_transform_with_canvas()
	return PackedVector2Array([transform * rect.position, transform * (rect.position + Vector2(rect.size.x, 0)), transform * rect.end, transform * (rect.position + Vector2(0, rect.size.y))])


func _paper_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if stamp_at(get_global_mouse_position()): _sheet.accept_event()


func _tween_focus(target: float) -> void:
	if _focus_tween != null and _focus_tween.is_valid(): _focus_tween.kill()
	_focus_tween = create_tween()
	_focus_tween.tween_property(self,"_focus_mix",target,_duration(focus_duration,0.22)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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


func _kill_feed_tween() -> void:
	if _feed_tween != null and _feed_tween.is_valid(): _feed_tween.kill()


func _duration(value: float, fallback: float) -> float:
	return clampf(value, 0.01, 10.0) if is_finite(value) and value > 0.0 else fallback


func _image(id: String, parent: Node) -> TextureRect:
	var image := TextureRect.new()
	image.name = id
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image


func _panel(id: String, parent: Node, color: Color) -> Panel:
	var panel := Panel.new()
	panel.name = id
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("59594b")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: style.set_border_width(side, 1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _label(id: String, text: String, parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.name = id
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color("252a23"))
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(id: String, text: String, parent: Node) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.add_theme_font_size_override("font_size", 14)
	parent.add_child(button)
	button.tooltip_text = ""
	if parent == _sheet:
		var style := load("res://scripts/demo/desk_paper_style.gd")
		if style != null: style.apply_button(button)
	return button
