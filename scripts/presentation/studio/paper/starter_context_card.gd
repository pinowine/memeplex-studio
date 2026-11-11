extends VBoxContainer

const Rules = preload("res://data/rules/design_rules.tres")
const Composition = preload("res://scripts/gameplay/design/meme_composition.gd")
const INK := Color("40463b")
var _record := {}
var _font: Font
var _localized: Array[Dictionary] = []

static func sample_text(record: Dictionary) -> String:
	var preset_id := str(record.get("id",""))
	if not Composition.supports(preset_id): return ""
	var draft: Dictionary = record.default_context.duplicate(true)
	draft.preset_id = preset_id
	var composed := Composition.compose(draft,[])
	var context: Array[String] = []
	for segment: Dictionary in composed.context_segments: context.append(str(segment.text))
	var parts: Array[String] = []
	if not context.is_empty(): parts.append(DeskLocalization.source_join("",context))
	parts.append(str(composed.expression))
	return DeskLocalization.source_join("\n",parts)

class ContextIcon extends Control:
	var kind := ""
	func _init() -> void:
		custom_minimum_size = Vector2(18, 18)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var color := Color("737958")
		match kind:
			"language":
				draw_arc(Vector2(9,9), 7, 0, TAU, 24, color, 1.2, true)
				draw_line(Vector2(2,9),Vector2(16,9),color,1.2,true)
				draw_line(Vector2(9,2),Vector2(9,16),color,1.2,true)
			"group":
				draw_arc(Vector2(6,5), 2.5, 0, TAU, 12, color, 1.2, true)
				draw_arc(Vector2(13,6), 2, 0, TAU, 12, color, 1.2, true)
				draw_arc(Vector2(6,15), 5, PI, TAU, 12, color, 1.2, true)
				draw_arc(Vector2(13,15), 4, PI, TAU, 12, color, 1.2, true)
			"topic":
				draw_polyline(PackedVector2Array([Vector2(2,3),Vector2(9,3),Vector2(16,10),Vector2(10,16),Vector2(2,8),Vector2(2,3)]),color,1.2,true)
				draw_circle(Vector2(5,6),1.2,color)
			"stance":
				draw_line(Vector2(2,9),Vector2(16,9),color,1.2,true)
				draw_line(Vector2(9,2),Vector2(9,16),color,1.2,true)
				draw_colored_polygon(PackedVector2Array([Vector2(9,3),Vector2(12,11),Vector2(6,11)]),color)
			"pragmatic":
				draw_polyline(PackedVector2Array([Vector2(2,3),Vector2(16,3),Vector2(16,12),Vector2(8,12),Vector2(4,16),Vector2(4,12),Vector2(2,12),Vector2(2,3)]),color,1.2,true)
				draw_line(Vector2(5,7),Vector2(13,7),color,1.2,true)

func configure(record: Dictionary, font: Font, show_description: bool = true) -> void:
	_record = record.duplicate(true)
	_font = font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	add_child(_label(str(record.title), 18))
	var sample := sample_text(record)
	if not sample.is_empty():
		var sample_label := _label(sample,16)
		sample_label.name = "StarterSample"
		add_child(sample_label)
	if show_description: add_child(_label(str(record.description), 13))
	var grid := GridContainer.new()
	grid.name = "DefaultContext"
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)
	var defaults: Dictionary = record.default_context
	var topics: Array[String] = []
	for id: String in defaults.topic_ids: topics.append(_context_title("topic", id))
	_field(grid, "topic", "LOC_STARTER_FIELD_TOPIC", topics)
	_field(grid, "language", "LOC_STARTER_FIELD_LANGUAGE", [_context_title("language", defaults.language_id)])
	_field(grid, "group", "LOC_STARTER_FIELD_GROUP", [_context_title("group", defaults.group_id)])
	_field(grid, "stance", "LOC_STARTER_FIELD_STANCE", _axis_words("stance", defaults.political_position) if bool(defaults.political_known) else ["LOC_STARTER_STANCE_UNSET"])
	_field(grid, "pragmatic", "LOC_STARTER_FIELD_PRAGMATICS", _axis_words("pragmatic", defaults.pragmatic_position))

func _axis_words(layer: String, point: Array) -> Array[String]:
	var axes := [["freedom", "authority"], ["equality", "hierarchy"]] if layer == "stance" else [["sincere", "ironic"], ["support", "opposition"]]
	var words: Array[String] = []
	for index in 2:
		var value := float(point[index])
		if not is_zero_approx(value):
			words.append(_context_title(layer + "_token", axes[index][1 if value > 0 else 0]))
	if words.is_empty(): words.append("LOC_STARTER_POLITICAL_NEUTRAL" if layer == "stance" else "LOC_STARTER_AXIS_CENTER")
	return words

func _context_title(kind: String, value: String) -> String:
	for definition: Dictionary in Rules.context_definitions.entries:
		if str(definition.kind) == kind and str(definition.value) == value:
			return str(definition.title)
	return value

func _field(grid: GridContainer, kind: String, heading: String, values: Array) -> void:
	var row := HBoxContainer.new()
	row.name = kind.capitalize()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	var icon := ContextIcon.new()
	icon.kind = kind
	row.add_child(icon)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 0)
	row.add_child(content)
	var title := _label(heading, 11)
	title.modulate = Color("747864")
	content.add_child(title)
	if values.size() > 1:
		var tags := HFlowContainer.new()
		tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tags.add_theme_constant_override("h_separation", 8)
		tags.add_theme_constant_override("v_separation", 0)
		content.add_child(tags)
		for value: String in values:
			var tag := _label(value, 13)
			tag.autowrap_mode = TextServer.AUTOWRAP_OFF
			tags.add_child(tag)
	else:
		for value: String in values: content.add_child(_label(value, 13))
	grid.add_child(row)

func _label(key_or_source: String, font_size: int) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", font_size)
	if _font != null: label.add_theme_font_override("font", _font)
	var key := str(DeskLocalization._aliases.get(key_or_source, key_or_source))
	label.text = DeskLocalization.text(key)
	label.set_meta("text_workbench_source", DeskLocalization.text_source(key))
	_localized.append({"label":label, "key":key})
	return label

func fit_width(width: float) -> void:
	size = Vector2(width, get_combined_minimum_size().y)
	for child: Control in get_children(): child.size.x = width

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		for item: Dictionary in _localized: item.label.text = DeskLocalization.text(item.key)

func inspection() -> Dictionary:
	return {"preset_id":_record.get("id", ""), "default_context":_record.get("default_context", {}).duplicate(true), "fields":5, "separate_labels":_localized.size()}
