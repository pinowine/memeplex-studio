extends RefCounted

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const CardFace = preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
const Handwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")

static func hover_info(control: Control) -> Dictionary:
	return {"title":str(control.help_title), "description":str(control.help_body),
		"kind":"impact" if str(control.help_kind) == "metric" else str(control.help_kind)}

class HelpLabel extends Label:
	var help_title := ""
	var help_body := ""
	var help_kind := "source"

	func set_help(title: String, body: String, kind: String = "source") -> void:
		help_title = title
		help_body = body
		help_kind = kind
		tooltip_text = ""
		mouse_filter = Control.MOUSE_FILTER_PASS if not body.is_empty() else Control.MOUSE_FILTER_IGNORE

class HelpButton extends Button:
	var help_title := ""
	var help_body := ""
	var help_kind := "source"

	func set_help(title: String, body: String, kind: String = "source") -> void:
		help_title = title
		help_body = body
		help_kind = kind
		tooltip_text = ""
		mouse_filter = Control.MOUSE_FILTER_PASS

class TagIcon extends Control:
	var kind := "language"
	var ink := Style.SECTION_TEAL

	func _init() -> void:
		custom_minimum_size = Vector2(16, 16)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Glyph.draw(self, Rect2(Vector2.ZERO, custom_minimum_size), kind, ink)

class TagChip extends PanelContainer:
	var help_title := ""
	var help_body := ""
	var help_kind := "language"
	var _label: Label
	var _icon: TagIcon

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", 4)
		add_child(line)
		_icon = TagIcon.new()
		line.add_child(_icon)
		_label = Label.new()
		_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.add_theme_font_override("font", Handwriting.BODY_FONT)
		_label.add_theme_font_size_override("font_size", 14)
		line.add_child(_label)

	func configure(tag: Dictionary, interactive: bool = true, compact: bool = false) -> void:
		help_title = str(tag.text)
		help_body = str(tag.help)
		help_kind = str(tag.kind)
		_label.text = help_title
		var font_size := 12 if compact else 14
		_label.add_theme_font_size_override("font_size", font_size)
		_icon.custom_minimum_size = Vector2(14, 14) if compact else Vector2(16, 16)
		custom_minimum_size.x = minf(256.0, ceilf(Handwriting.BODY_FONT.get_string_size(help_title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + (30.0 if compact else 34.0)))
		_icon.kind = help_kind
		var ink: Color
		var fill: Color
		var edge: Color
		if CardFace.PALETTES.has(help_kind):
			var palette: Dictionary = CardFace.PALETTES[help_kind]
			ink = palette.ink
			fill = palette.panel
			edge = Color(palette.edge, 0.35)
		else:
			ink = Style.SECTION_PURPLE
			fill = Color(Style.SECTION_PURPLE, 0.10)
			edge = Color(Style.SECTION_PURPLE, 0.30)
		var paper := StyleBoxFlat.new()
		paper.bg_color = fill
		paper.border_color = edge
		paper.set_border_width_all(1)
		paper.set_corner_radius_all(3)
		paper.content_margin_left = 4 if compact else 6
		paper.content_margin_right = 6 if compact else 8
		paper.content_margin_top = 2 if compact else 4
		paper.content_margin_bottom = 2 if compact else 4
		add_theme_stylebox_override("panel", paper)
		_label.add_theme_color_override("font_color", ink)
		_icon.ink = ink
		_icon.queue_redraw()
		tooltip_text = ""
		mouse_filter = Control.MOUSE_FILTER_PASS if interactive else Control.MOUSE_FILTER_IGNORE

	func inspection() -> Dictionary:
		return {"text":help_title, "kind":help_kind, "help":help_body, "tooltip_text":tooltip_text,
			"mouse_filter":mouse_filter, "size":size, "minimum_size":get_combined_minimum_size()}
