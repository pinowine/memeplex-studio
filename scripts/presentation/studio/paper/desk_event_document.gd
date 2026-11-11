extends ScrollContainer

const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Handwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")

class SectionIcon extends Control:
	var kind := "source"
	var ink := Style.SECTION_TEAL

	func _init() -> void:
		custom_minimum_size = Vector2(24, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Glyph.draw(self, Rect2(Vector2.ZERO, Vector2(24, 24)), kind, ink)

var _column: VBoxContainer
var _blocks: Array[Dictionary] = []
var _numbers := RegEx.create_from_string("[-+]?[0-9]+(?:[.,][0-9]+)*(?:%|％)?")

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 16)
	add_child(_column)

func set_blocks(blocks: Array[Dictionary], full_title: String = "") -> void:
	_blocks = blocks.duplicate(true)
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	if not full_title.is_empty():
		var title := _label(full_title, 20, Style.INK)
		_column.add_child(title)
	for index in blocks.size():
		var block: Dictionary = blocks[index]
		var role := str(block.get("role", ""))
		if index > 0 and role != "narrative":
			var rule := HSeparator.new()
			var line := StyleBoxLine.new()
			line.color = Style.EDGE
			rule.add_theme_stylebox_override("separator", line)
			_column.add_child(rule)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_column.add_child(row)
		var icon := SectionIcon.new()
		icon.kind = str(block.get("kind", "source"))
		icon.ink = Style.SECTION_BROWN if role == "commentary" else Style.SECTION_TEAL
		row.add_child(icon)
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 8)
		row.add_child(content)
		var heading := str(block.get("heading", ""))
		if not heading.is_empty(): content.add_child(_label(heading, 16, Style.SECONDARY_INK))
		var body := RichTextLabel.new()
		body.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		body.bbcode_enabled = false
		body.fit_content = true
		body.scroll_active = false
		body.selection_enabled = true
		body.mouse_filter = Control.MOUSE_FILTER_PASS
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_theme_font_override("normal_font", Handwriting.BODY_FONT)
		body.add_theme_font_override("bold_font", Handwriting.BOLD_FONT)
		var font_size := 14 if role == "metadata" else (16 if role == "commentary" else 18)
		body.add_theme_font_size_override("normal_font_size", font_size)
		body.add_theme_font_size_override("bold_font_size", font_size)
		body.add_theme_color_override("default_color", Style.SECONDARY_INK if role in ["metadata", "commentary"] else Style.INK)
		body.add_theme_constant_override("line_separation", 6)
		content.add_child(body)
		_write_content(body, str(block.get("content", "")))

func _label(text: String, font_size: int, ink: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", Handwriting.BOLD_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	return label

func _write_content(label: RichTextLabel, text: String) -> void:
	var cursor := 0
	for number: RegExMatch in _numbers.search_all(text):
		label.add_text(text.substr(cursor, number.get_start() - cursor))
		label.push_bold()
		label.push_color(Style.SECTION_BROWN)
		label.add_text(number.get_string())
		label.pop()
		label.pop()
		cursor = number.get_end()
	label.add_text(text.substr(cursor))

func inspection() -> Dictionary:
	return {"blocks":_blocks.duplicate(true), "scrollable":true, "content_height":_column.size.y,
		"viewport_height":size.y, "horizontal_overflow":_column.size.x > size.x + 1}
