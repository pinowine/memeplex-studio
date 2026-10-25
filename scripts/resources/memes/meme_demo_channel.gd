class_name MemeDemoChannel
extends Resource

@export var id: StringName
@export var title: String = ""
@export var reach_factor: float = 1.0
@export var remix_factor: float = 1.0
@export_multiline var description: String = ""
@export var evidence_status: StringName = &"design"

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id.is_empty() or title.strip_edges().is_empty() or description.strip_edges().is_empty():
		errors.append("Channel ID, title and description are required")
	if not is_finite(reach_factor) or reach_factor < 0.0:
		errors.append("Channel reach must be finite and nonnegative")
	if not is_finite(remix_factor) or remix_factor < 0.0:
		errors.append("Channel remix must be finite and nonnegative")
	if evidence_status != &"design":
		errors.append("Channel factors must identify design evidence")
	return errors
