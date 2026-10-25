class_name MemeDemoKernel
extends Resource

@export var id: StringName
@export var title: String = ""
@export_multiline var description: String = ""
@export var required_slots: PackedStringArray = PackedStringArray()
@export var slot_prompts: PackedStringArray = PackedStringArray()
@export var default_values: PackedStringArray = PackedStringArray()
@export var family_anchor: String = ""
@export var split_threshold: float = 0.6
@export var evidence_status: StringName = &"design"

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty() or title.strip_edges().is_empty() or description.strip_edges().is_empty():
		errors.append("Kernel ID, title and description are required")
	if required_slots.size() < 3 or required_slots.size() > 5:
		errors.append("Demo kernels expose 3 to 5 editable slots")
	if required_slots.size() != slot_prompts.size() or required_slots.size() != default_values.size():
		errors.append("Kernel slot fields must have equal lengths")
	var seen: Dictionary = {}
	for slot in required_slots:
		if slot.strip_edges().is_empty() or seen.has(slot):
			errors.append("Kernel slots must be nonempty and unique")
		seen[slot] = true
	for prompt in slot_prompts:
		if prompt.strip_edges().is_empty():
			errors.append("Slot prompts cannot be blank")
	for default_value in default_values:
		if default_value.strip_edges().is_empty():
			errors.append("Default slot values cannot be blank")
	if family_anchor.strip_edges().is_empty():
		errors.append("A family anchor is required")
	if not is_finite(split_threshold) or split_threshold <= 0.0 or split_threshold > 1.0:
		errors.append("Split threshold must be in (0, 1]")
	if evidence_status != &"design":
		errors.append("Kernel slots and threshold are design abstractions")
	return errors
