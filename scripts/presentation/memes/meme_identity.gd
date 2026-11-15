extends RefCounted

const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")

static func name(catalog: MemeDemoCatalog, raw: Dictionary) -> String:
	var meme_name := str(raw.get("meme_name", ""))
	if not meme_name.is_empty():
		var title := DeskLocalization.text(str(raw.get("split_parent_name", meme_name)))
		var name_index := int(raw.get("meme_name_index", -1))
		if raw.has("split_parent_name") or raw.has("split_from_id"): return "%s-%d" % [title, name_index + 1]
		return "%s %d" % [title, name_index / 16 + 1] if name_index >= 16 else title
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
	var kind := "MAP_MEME_OWN" if bool(raw.get("controlled", false)) and str(raw.get("creator", "")) == "player" else "MAP_MEME_INDEPENDENT"
	return {"name":name(catalog, raw), "expression":display_text(str(raw.get("text", ""))),
		"meaning":display_text(meaning),
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
