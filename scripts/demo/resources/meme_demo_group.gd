class_name MemeDemoGroup
extends Resource

@export var id: StringName
@export var title: String = ""
@export var tag_ids: PackedStringArray = PackedStringArray()
@export var topic_ids: PackedStringArray = PackedStringArray()
@export var topic_affinities: PackedFloat32Array = PackedFloat32Array()
@export var sample_size: int = 2000
@export var language_id: StringName = &"zh"
@export var political_position: Vector2 = Vector2.ZERO
@export var evidence_status: StringName = &"design"
@export var language_access: float = 0.8
@export var recognizability: float = 0.7
@export var attention_fraction: float = 0.12

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty() or title.strip_edges().is_empty() or language_id.is_empty():
		errors.append("Group ID, title and language are required")
	if sample_size <= 0:
		errors.append("Synthetic group sample must be positive")
	if evidence_status != &"design":
		errors.append("Group parameters must identify design evidence")
	if topic_ids.size() != topic_affinities.size():
		errors.append("Topic IDs and affinities must have equal lengths")
	for affinity in topic_affinities:
		if not is_finite(affinity) or affinity < 0.0 or affinity > 1.0:
			errors.append("Topic affinity must be in [0, 1]")
	for value in [language_access, recognizability, attention_fraction]:
		if not is_finite(value) or value < 0.0 or value > 1.0:
			errors.append("Language access, recognition and attention fraction must be in [0, 1]")
	if not political_position.is_finite() or absf(political_position.x) > 1.0 or absf(political_position.y) > 1.0:
		errors.append("Political coordinates must be finite and in [-1, 1]")
	for values in [tag_ids, topic_ids]:
		var seen: Dictionary = {}
		for value in values:
			if String(value).strip_edges().is_empty() or seen.has(value):
				errors.append("Group tags and topics must be nonempty and unique")
			seen[value] = true
	return errors
