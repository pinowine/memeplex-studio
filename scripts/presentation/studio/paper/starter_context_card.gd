extends VBoxContainer

const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")
const Rules = preload("res://data/rules/design_rules.tres")
const Composition = preload("res://scripts/gameplay/design/meme_composition.gd")
const ContextTagFlow = preload("res://scripts/presentation/context/context_tag_flow.gd")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const MemeExpression = preload("res://scripts/presentation/studio/workbench/desk_meme_expression.gd")
const INK := Color("40463b")
var _record := {}
var _font: Font
var _localized: Array[Dictionary] = []
var _tag_fields: Array[Dictionary] = []

static func _compose_sample(record: Dictionary) -> Dictionary:
	var preset_id := str(record.get("id",""))
	if not Composition.supports(preset_id): return {}
	var draft: Dictionary = record.default_context.duplicate(true)
	draft.preset_id = preset_id
	return Composition.compose(draft, [])

static func sample_text(record: Dictionary) -> String:
	var composed := _compose_sample(record)
	if composed.is_empty(): return ""
	var context: Array[String] = []
	for segment: Dictionary in composed.context_segments: context.append(str(segment.text))
	var parts: Array[String] = []
	if not context.is_empty(): parts.append(DeskLocalization.source_join("",context))
	parts.append(str(composed.expression))
	return DeskLocalization.source_join("\n",parts)

func configure(record: Dictionary, font: Font, show_context: bool = true) -> void:
	_record = record.duplicate(true)
	_font = font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	add_child(_label(str(record.title), 18))
	var composed := _compose_sample(record)
	if not composed.is_empty():
		var frame := PanelContainer.new()
		frame.name = "SampleFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(PaperStyle.EDGE, .12)
		for side: int in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]: style.set_content_margin(side, 8)
		frame.add_theme_stylebox_override("panel", style)
		add_child(frame)
		if "\n" in str(composed.expression) or not composed.context_segments.is_empty():
			var preview := MemeExpression.new()
			preview.name = "StarterExpression"
			preview.set_interaction_enabled(false)
			preview.configure(str(record.id), composed.expression_segments, composed.context_segments, str(composed.expression), true)
			frame.add_child(preview)
		else:
			var sample := _label(str(composed.expression), 16)
			sample.name = "StarterSample"
			frame.add_child(sample)
	var note := _label(str(record.description), 13)
	note.name = "StarterNote"
	Typography.apply_control(note, "hint")
	add_child(note)
	if not show_context: return
	var grid := VBoxContainer.new()
	grid.name = "DefaultContext"
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("separation", 4)
	add_child(grid)
	var defaults: Dictionary = record.default_context
	var topics: Array[String] = []
	for id: String in defaults.topic_ids: topics.append(_context_title("topic", id))
	_field(grid, "topic", topics)
	_field(grid, "language", [_context_title("language", defaults.language_id)])
	_field(grid, "group", [_context_title("group", defaults.group_id)])
	_field(grid, "stance", _axis_words("stance", defaults.political_position) if bool(defaults.political_known) else ["LOC_STARTER_STANCE_UNSET"])
	_field(grid, "pragmatic", _axis_words("pragmatic", defaults.pragmatic_position))

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

func _field(grid: VBoxContainer, kind: String, values: Array) -> void:
	var tags := ContextTagFlow.new()
	tags.name = kind.capitalize()
	tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tags.set_tags(_context_tags(kind, values))
	grid.add_child(tags)
	_tag_fields.append({"flow":tags, "kind":kind, "values":values.duplicate()})

func _context_tags(kind: String, values: Array) -> Array[Dictionary]:
	var tags: Array[Dictionary] = []
	for value: String in values:
		tags.append({"text":DeskLocalization.text(value), "kind":kind, "help":""})
	return tags

func _label(key_or_source: String, font_size: int) -> Label:
	var text_role := Typography.role_for_size(font_size)
	font_size = Typography.normalized_size(font_size)
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
	Typography.apply_control(label, text_role, true)
	return label

func fit_width(width: float) -> void:
	for field: Dictionary in _tag_fields: field.flow.fit_width(width)
	size = Vector2(width, get_combined_minimum_size().y)
	for child: Control in get_children(): child.size.x = width

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		for item: Dictionary in _localized: item.label.text = DeskLocalization.text(item.key)
		for field: Dictionary in _tag_fields: field.flow.set_tags(_context_tags(str(field.kind), field["values"]))

func inspection() -> Dictionary:
	var tags: Array = []
	for field: Dictionary in _tag_fields: tags.append(field.flow.inspection())
	return {"preset_id":_record.get("id", ""), "default_context":_record.get("default_context", {}).duplicate(true), "fields":_tag_fields.size(), "separate_labels":_localized.size(), "context_tags":tags}
