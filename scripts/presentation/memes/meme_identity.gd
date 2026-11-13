extends RefCounted

const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")

static func name(catalog: MemeDemoCatalog, raw: Dictionary) -> String:
	var preset := catalog.find_preset(_preset_id(raw))
	if preset != null: return ExpressionText.preset_name(preset, true)
	return " ".join(display_text(str(raw.get("text", ""))).split("\n", false))

static func resolve(catalog: MemeDemoCatalog, raw: Dictionary) -> Dictionary:
	var meaning := str(raw.get("meaning", ""))
	var draft: Dictionary = raw.get("flow_draft", {})
	if meaning.is_empty() and not draft.is_empty() and ExpressionText.Composition.supports(str(draft.get("preset_id", ""))):
		meaning = str(ExpressionText.compose(catalog, draft).get("meaning", ""))
	if meaning.is_empty(): meaning = str(raw.get("event_reading", {}).get("frame", ""))
	if meaning.is_empty():
		var preset := catalog.find_preset(_preset_id(raw))
		if preset != null: meaning = str(preset.context_hint)
	var id := str(raw.get("id", ""))
	var suffix := id.get_slice("_", id.get_slice_count("_") - 1)
	var kind := "MAP_MEME_OWN" if bool(raw.get("controlled", false)) and str(raw.get("creator", "")) == "player" else ("MAP_MEME_REMIX" if not raw.get("parent_ids", []).is_empty() else "MAP_MEME_INDEPENDENT")
	return {"name":name(catalog, raw), "expression":display_text(str(raw.get("text", ""))),
		"meaning":display_text(meaning), "version":str(int(suffix)) if suffix.is_valid_int() else id,
		"kind":DeskLocalization.text(kind)}

static func display_text(value: String) -> String:
	var text := DeskLocalization.text(value)
	return text.replace("·", "\n").replace("／", "\n").replace(" / ", "\n")

static func _preset_id(raw: Dictionary) -> String:
	var id := str(raw.get("preset_id", ""))
	if not id.is_empty(): return id
	id = str(raw.get("flow_draft", {}).get("preset_id", ""))
	if not id.is_empty(): return id
	for source: Dictionary in raw.get("source_presets", []):
		id = str(source.preset_id)
		if not id.is_empty(): return id
	return ""
