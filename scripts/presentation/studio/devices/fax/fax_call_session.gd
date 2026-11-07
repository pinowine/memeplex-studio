extends RefCounted

signal call_changed(record: Dictionary)
signal starter_selected(preset_id: String)
signal startup_finished(preset_id: String)

static var REPLIES := [DeskLocalization.source("LOC_POINT_OUT_THE_CONDITIONS_THIS_MESSAGE_LEAVES_F3A0979C"), DeskLocalization.source("LOC_RECORD_IT_FIRST_DON_T_DRAW_MY_D888BD63")]
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
var diagnostic := DeskLocalization.source("LOC_LOCAL_CONNECTIONS_ONLY_NO_REAL_PHONE_CALLS_854E21C9")
var _context_event: Dictionary = {}

func _init() -> void:
	set_contacts([])

func set_context(event: Dictionary) -> void:
	_context_event = event

func set_contacts(values: Array) -> void:
	contacts.clear()
	contacts.append({"number":"67#", "name":"67", "identity":DeskLocalization.source("LOC_YOUR_ASSISTANT_INTELLIGENCE_COLLECTION_AND_TRANSMISSION_OBSERVAT_7FF267F2"), "greeting":DeskLocalization.source("LOC_THE_LINE_WORKS_WHETHER_THE_MESSAGE_DESERVES_CE70DE5C")})
	for contact: Variant in values:
		if contact is Dictionary: add_contact(contact)

func add_contact(contact: Dictionary) -> bool:
	var number := str(contact.get("number", "")).strip_edges()
	if not _valid_number(number) or str(contact.get("name", "")).strip_edges().is_empty(): return false
	for known: Dictionary in contacts:
		if str(known.number) == number: return false
	contacts.append({"number":number, "name":str(contact.name), "identity":str(contact.get("identity", DeskLocalization.source("LOC_COLLECTED_CONTACT_FE5E6233"))), "greeting":str(contact.get("greeting", DeskLocalization.source("LOC_CONNECTED_THE_OTHER_PARTY_HAS_NO_FURTHER_574C388B")))})
	return true

func select_contact(index: int, enabled: bool) -> bool:
	if not enabled or index < 0 or index >= contacts.size(): return false
	dialed_number = str(contacts[index].number)
	state = "idle"
	selected_contact = {}
	diagnostic = DeskLocalization.source("LOC_NUMBER_COPIED_FROM_THE_PHONE_BOOK_DIAL_4C584176")
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
	diagnostic = DeskLocalization.source("LOC_IS_CALLING_PICK_UP_AND_HEAR_ALL_27A63F88")
	return true

func starter_call(enabled: bool) -> bool:
	return enabled and state == "connected" and dialed_number == "67#" and not startup_done and not starter_options.is_empty()

func confirm_starter(preset_id: String, enabled: bool) -> bool:
	if not starter_call(enabled) or preset_id != pending_starter_id: return false
	starter_id = preset_id
	pending_starter_id = ""
	for option: Dictionary in starter_options:
		if str(option.id) == preset_id: selected_reply = DeskLocalization.source("LOC_SELECTED_AB41B55D") + str(option.title)
	_append_call("starter_confirmed", DeskLocalization.source("LOC_GUIDE_STARTER_CONFIRMED"))
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
	diagnostic = DeskLocalization.source("LOC_NUMBERS_ARE_MATCHED_AGAINST_THE_LOCAL_PHONE_32C3D8DB")
	return true

func dial(enabled: bool) -> bool:
	if not enabled or state == "connected": return false
	selected_contact = {}
	if _valid_number(dialed_number):
		for contact: Dictionary in contacts:
			if str(contact.number) == dialed_number: selected_contact = contact.duplicate(true)
	if selected_contact.is_empty():
		state = "invalid"
		diagnostic = DeskLocalization.source("LOC_NO_ANSWER_UNLISTED_NUMBER_OR_INVALID_FORMAT_F9B2A597")
		_append_call("no_answer", DeskLocalization.source("LOC_THAT_NUMBER_ISN_T_IN_THE_PHONE_7C770EF9"))
		return false
	state = "dial_ready"
	diagnostic = DeskLocalization.source_format("LOC_FOUND_S_PICK_UP_THE_RECEIVER_TO_A1F554ED", str(selected_contact.name))
	return true

func pickup(enabled: bool) -> bool:
	if not enabled or state not in ["dial_ready", "incoming"] or selected_contact.is_empty(): return false
	state = "connected"
	var line := str(selected_contact.greeting)
	if dialed_number == "67#" and not DeskLocalization.text(str(_context_event.get("mentor_comment", ""))).strip_edges().is_empty():
		line = str(_context_event.mentor_comment)
	diagnostic = DeskLocalization.source_format("LOC_LOCAL_CONNECTION_S_DE115FAE", str(selected_contact.name))
	_append_call("connected", line)
	return true

func hangup(enabled: bool, can_choose_starter: bool) -> bool:
	if not enabled or state not in ["connected", "dial_ready", "incoming"]: return false
	var finish_startup := starter_call(can_choose_starter) and not starter_id.is_empty()
	_append_call("hangup", DeskLocalization.source("LOC_CALL_ENDED_THE_FACTS_STAY_ON_PAPER_58CCE8D4"))
	state = "idle"
	selected_contact = {}
	diagnostic = DeskLocalization.source("LOC_RECEIVER_REPLACED_8F848FA7")
	if finish_startup:
		startup_done = true
		startup_finished.emit(starter_id)
	return true

func choose_response(index: int, enabled: bool) -> bool:
	if starter_call(enabled):
		if index < 0 or index >= starter_options.size() or not pending_starter_id.is_empty() or not starter_id.is_empty(): return false
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
	var record := {"index":call_log.size(), "number":dialed_number, "name":str(selected_contact.get("name", DeskLocalization.source("LOC_NOT_COLLECTED_01C47B74"))), "kind":kind, "text":text, "event_id":event_id if dialed_number == "67#" and kind == "connected" else "", "context_event_id":event_id, "local_only":true}
	call_log.append(record)
	call_changed.emit(record.duplicate(true))
