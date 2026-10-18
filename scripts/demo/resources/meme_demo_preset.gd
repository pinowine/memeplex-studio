class_name MemeDemoPreset
extends Resource

@export var id: StringName
@export var kernel_id: StringName
@export var title: String = ""
@export var required_slots: PackedStringArray = PackedStringArray()
@export var slot_prompts: PackedStringArray = PackedStringArray()
@export var default_values: PackedStringArray = PackedStringArray()
@export_multiline var family_anchor: String = ""
@export_multiline var context_hint: String = ""
@export var source_case_id: String = ""
@export var source_path: String = ""
@export var source_sha256: String = ""
@export var source_document_path: String = ""
@export var source_document_sha256: String = ""
@export var source_url: String = ""
@export var evidence_status: StringName = &"design_abstraction"

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty() or kernel_id.is_empty() or title.strip_edges().is_empty():
		errors.append("Preset ID, kernel and title are required")
	if required_slots.size() < 3 or required_slots.size() > 5 or required_slots.size() != slot_prompts.size() or required_slots.size() != default_values.size():
		errors.append("Preset slot fields must contain 3 to 5 matching entries")
	var seen: Dictionary = {}
	for slot in required_slots:
		if slot.strip_edges().is_empty() or seen.has(slot): errors.append("Preset slot IDs must be nonempty and unique")
		seen[slot] = true
	for value in slot_prompts + default_values:
		if value.strip_edges().is_empty(): errors.append("Preset prompts and defaults cannot be blank")
	if family_anchor.strip_edges().is_empty() or context_hint.strip_edges().is_empty() or source_case_id.is_empty():
		errors.append("Preset anchor, context and source case are required")
	for path in [source_path, source_document_path]:
		if not path.is_absolute_path(): errors.append("Preset source paths must be absolute")
	for hash_value in [source_sha256, source_document_sha256]:
		if hash_value.length() != 64 or not hash_value.is_valid_hex_number(false): errors.append("Preset source hashes must be SHA-256 hex strings")
	if not source_url.begins_with("https://") or evidence_status != &"design_abstraction":
		errors.append("Preset provenance must distinguish a design abstraction from evidence")
	return errors

func to_draft(base: Dictionary) -> Dictionary:
	var draft := base.duplicate(true)
	draft.preset_id = str(id)
	draft.kernel_id = str(kernel_id)
	var slots: Dictionary = {}
	for index in required_slots.size(): slots[required_slots[index]] = default_values[index]
	draft.slots = slots
	draft.replaceable_slots = required_slots.duplicate()
	return draft

func source_record() -> Dictionary:
	return {"preset_id":str(id), "case_id":source_case_id, "path":source_path, "sha256":source_sha256, "document_path":source_document_path, "document_sha256":source_document_sha256, "url":source_url}
