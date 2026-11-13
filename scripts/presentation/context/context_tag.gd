extends PanelContainer

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const Glyph = preload("res://scripts/presentation/studio/paper/desk_receipt_glyph.gd")
const CardFace = preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
const Handwriting = preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")

class TagIcon extends Control:
	var kind := "language"
	var ink := Style.SECTION_TEAL

	func _init() -> void:
		custom_minimum_size = Vector2(14, 14)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		Glyph.draw(self, Rect2(Vector2.ZERO, custom_minimum_size), kind, ink)

var help_title := ""
var help_body := ""
var help_kind := "language"
var _label: Label
var _icon: TagIcon
var _preferred_width := 0.0

static func palette(kind: String) -> Dictionary:
	if CardFace.PALETTES.has(kind):
		var colors: Dictionary = CardFace.PALETTES[kind]
		return {"ink":colors.ink, "fill":colors.panel, "edge":Color(colors.edge, 0.35)}
	return {"ink":Style.SECTION_PURPLE, "fill":Color(Style.SECTION_PURPLE, 0.10), "edge":Color(Style.SECTION_PURPLE, 0.30)}

static func paper(kind: String) -> StyleBoxFlat:
	var colors := palette(kind)
	var box := StyleBoxFlat.new()
	box.bg_color = colors.fill
	box.border_color = colors.edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 4
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box

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
	_label.add_theme_font_size_override("font_size", 12)
	line.add_child(_label)

func configure(tag: Dictionary) -> void:
	help_title = str(tag.text)
	help_body = str(tag.help)
	help_kind = str(tag.kind)
	_label.text = help_title
	_preferred_width = minf(256.0, ceilf(Handwriting.BODY_FONT.get_string_size(help_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 30.0))
	fit_width(_preferred_width)
	_icon.kind = help_kind
	var colors := palette(help_kind)
	add_theme_stylebox_override("panel", paper(help_kind))
	_label.add_theme_color_override("font_color", colors.ink)
	_icon.ink = colors.ink
	_icon.queue_redraw()

func fit_width(width: float) -> void:
	custom_minimum_size.x = minf(_preferred_width, width)

func inspection() -> Dictionary:
	return {"text":help_title, "kind":help_kind, "help":help_body, "tooltip_text":tooltip_text,
		"mouse_filter":mouse_filter, "size":size, "minimum_size":get_combined_minimum_size()}
