extends RefCounted

signal call_changed(record: Dictionary)
signal starter_selected(preset_id: String)
signal startup_finished(preset_id: String)

const REPLIES := ["请指出这份消息漏掉的条件。", "先记录，不替我下结论。"]
var contacts: Array[Dictionary] = []
var call_log: Array[Dictionary] = []
var state := "idle"
var dialed_number := "67#"
var selected_contact: Dictionary = {}
var selected_reply := ""
var starter_options: Array[Dictionary] = []
var starter_id := ""
var pending_starter_id := ""
var startup_done := false
var diagnostic := "仅本地接线，不拨打真实电话。"
var _context_event: Dictionary = {}

func _init() -> void:
	set_contacts([])

func set_context(event: Dictionary) -> void:
	_context_event = event

func set_contacts(values: Array) -> void:
	contacts.clear()
	contacts.append({"number":"67#", "name":"67", "identity":"你的助手 / 情报收集与传播观察", "greeting":"线路是通的。消息是否值得转发，是另一笔账。"})
	for contact: Variant in values:
		if contact is Dictionary: add_contact(contact)

func add_contact(contact: Dictionary) -> bool:
	var number := str(contact.get("number", "")).strip_edges()
	if not _valid_number(number) or str(contact.get("name", "")).strip_edges().is_empty(): return false
	for known: Dictionary in contacts:
		if str(known.number) == number: return false
	contacts.append({"number":number, "name":str(contact.name), "identity":str(contact.get("identity", "已收录联系人")), "greeting":str(contact.get("greeting", "线路接通。对方没有补充消息。"))})
	return true

func select_contact(index: int, enabled: bool) -> bool:
	if not enabled or index < 0 or index >= contacts.size(): return false
	dialed_number = str(contacts[index].number)
	state = "idle"
	selected_contact = {}
	diagnostic = "已抄入电话簿号码；拨号后才能拿起听筒。"
	return true

func offer_starters(options: Array, selected_id: String) -> bool:
	if options.size() != 3: return false
	var choices: Array[Dictionary] = []
	var ids: Array[String] = []
	for option: Variant in options:
		if not option is Dictionary or not option.get("id") is String or not option.get("title") is String: return false
		var id := str(option.id).strip_edges()
		if id.is_empty() or str(option.title).strip_edges().is_empty() or id in ids: return false
		ids.append(id)
		choices.append(option.duplicate(true))
	if not selected_id.is_empty() and selected_id not in ids: return false
	starter_options = choices
	starter_id = selected_id
	pending_starter_id = ""
	startup_done = false
	selected_reply = ""
	dialed_number = "67#"
	selected_contact = contacts[0].duplicate(true)
	state = "incoming"
	diagnostic = "67 来电。拿起听筒，听完三份起始模因再作选择。"
	return true

func starter_call(enabled: bool) -> bool:
	return enabled and state == "connected" and dialed_number == "67#" and not startup_done and not starter_options.is_empty()

func confirm_starter(preset_id: String, enabled: bool) -> bool:
	if not starter_call(enabled) or preset_id != pending_starter_id: return false
	starter_id = preset_id
	pending_starter_id = ""
	for option: Dictionary in starter_options:
		if str(option.id) == preset_id: selected_reply = "选择：" + str(option.title)
	_append_call("starter_confirmed", "选好了。放回听筒后，到稿纸上编辑、培养，再决定怎样传播。")
	return true

func reject_starter(message: String) -> void:
	pending_starter_id = ""
	diagnostic = message

func clear_starter_offer() -> void:
	starter_options.clear()
	starter_id = ""
	pending_starter_id = ""
	startup_done = false

func keypad_key(key: String, enabled: bool) -> bool:
	if not enabled or state == "connected": return false
	if key == "backspace":
		dialed_number = dialed_number.left(maxi(0, dialed_number.length() - 1))
	elif key == "clear":
		dialed_number = ""
	elif key.length() == 1 and key in "0123456789#":
		if dialed_number.length() >= 12: return false
		dialed_number += key
	else:
		return false
	state = "idle"
	selected_contact = {}
	diagnostic = "号码只在本地电话簿中匹配。"
	return true

func dial(enabled: bool) -> bool:
	if not enabled or state == "connected": return false
	selected_contact = {}
	if _valid_number(dialed_number):
		for contact: Dictionary in contacts:
			if str(contact.number) == dialed_number: selected_contact = contact.duplicate(true)
	if selected_contact.is_empty():
		state = "invalid"
		diagnostic = "无人应答：号码未收录或格式无效。"
		_append_call("no_answer", "电话簿没有这个号码。空号不会因为你多拨一次就升职。")
		return false
	state = "dial_ready"
	diagnostic = DeskLocalization.source_format("已找到 %s；拿起听筒接线。", str(selected_contact.name))
	return true

func pickup(enabled: bool) -> bool:
	if not enabled or state not in ["dial_ready", "incoming"] or selected_contact.is_empty(): return false
	state = "connected"
	var line := str(selected_contact.greeting)
	if dialed_number == "67#" and not DeskLocalization.text(str(_context_event.get("mentor_comment", ""))).strip_edges().is_empty():
		line = str(_context_event.mentor_comment)
	diagnostic = DeskLocalization.source_format("本地接线 / %s", str(selected_contact.name))
	_append_call("connected", line)
	return true

func hangup(enabled: bool, can_choose_starter: bool) -> bool:
	if not enabled or state not in ["connected", "dial_ready", "incoming"]: return false
	var finish_startup := starter_call(can_choose_starter) and not starter_id.is_empty()
	_append_call("hangup", "接线结束。事实留在纸上，不占用听筒。")
	state = "idle"
	selected_contact = {}
	diagnostic = "听筒已放回。"
	if finish_startup:
		startup_done = true
		startup_finished.emit(starter_id)
	return true

func choose_response(index: int, enabled: bool) -> bool:
	if starter_call(enabled):
		if index < 0 or index >= starter_options.size() or not pending_starter_id.is_empty(): return false
		pending_starter_id = str(starter_options[index].id)
		# The simulation must confirm the choice before this session commits it.
		starter_selected.emit(pending_starter_id)
		return true
	if not enabled or state != "connected" or index < 0 or index >= REPLIES.size(): return false
	selected_reply = str(REPLIES[index])
	_append_call("player_option", selected_reply)
	return true

func reset() -> void:
	state = "idle"
	dialed_number = "67#"
	selected_contact.clear()
	selected_reply = ""
	clear_starter_offer()
	call_log.clear()
	_context_event = {}
	set_contacts([])

func _valid_number(number: String) -> bool:
	if number.length() < 2 or number.length() > 12 or not number.ends_with("#"): return false
	for character in number.left(number.length() - 1):
		if character not in "0123456789": return false
	return true

func _append_call(kind: String, text: String) -> void:
	var event_id := str(_context_event.get("instance_id", ""))
	var record := {"index":call_log.size(), "number":dialed_number, "name":str(selected_contact.get("name", "未收录")), "kind":kind, "text":text, "event_id":event_id if dialed_number == "67#" and kind == "connected" else "", "context_event_id":event_id, "local_only":true}
	call_log.append(record)
	call_changed.emit(record.duplicate(true))
