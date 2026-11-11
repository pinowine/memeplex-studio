class_name DeskReceiptUI
extends RefCounted

const Style = preload("res://scripts/presentation/studio/paper/desk_receipt_style.gd")
const BODY_FONT = preload("res://assets/image/fonts/development_font.tres")
const MEDIUM_FONT = preload("res://assets/image/fonts/body_medium_font.tres")
const BOLD_FONT = preload("res://assets/image/fonts/body_bold_font.tres")

static func _box(fill: Color, border: Color, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_border_width_all(width)
	box.border_color = border
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

static func create_theme() -> Theme:
	var result: Theme = preload("res://data/presentation/ui/receipt_tooltip_theme.tres").duplicate()
	result.default_font_size = 16
	result.set_font("font", "Label", BODY_FONT)
	result.set_font("font", "Button", MEDIUM_FONT)
	result.set_font("font", "OptionButton", MEDIUM_FONT)
	result.set_color("font_color", "Label", Style.INK)
	result.set_color("default_color", "RichTextLabel", Style.INK)
	result.set_constant("line_separation", "RichTextLabel", 4)
	result.set_type_variation("ReceiptHeading", "Label")
	result.set_font("font", "ReceiptHeading", BOLD_FONT)
	result.set_font_size("font_size", "ReceiptHeading", 28)
	for type: String in ["Button", "OptionButton", "CheckButton"]:
		result.set_color("font_color", type, Style.INK)
		result.set_color("font_hover_color", type, Style.INK)
		result.set_color("font_pressed_color", type, Style.INK)
		result.set_color("font_disabled_color", type, Style.SECONDARY_INK)
		result.set_color("font_focus_color", type, Style.INK)
		result.set_color("font_outline_color", type, Color.TRANSPARENT)
		result.set_stylebox("normal", type, _box(Color.TRANSPARENT, Style.EDGE))
		result.set_stylebox("hover", type, _box(Color(Style.EDGE, .20), Style.SECONDARY_INK))
		result.set_stylebox("pressed", type, _box(Color(Style.EDGE, .36), Style.INK))
		result.set_stylebox("disabled", type, _box(Color.TRANSPARENT, Color(Style.EDGE, .5)))
		result.set_stylebox("focus", type, _box(Color.TRANSPARENT, Style.SECTION_TEAL, 2))
	result.set_stylebox("panel", "PopupMenu", load("res://data/presentation/ui/receipt_tooltip_style.tres"))
	result.set_font("font", "PopupMenu", BODY_FONT)
	result.set_color("font_color", "PopupMenu", Style.INK)
	result.set_color("font_hover_color", "PopupMenu", Style.INK)
	result.set_stylebox("hover", "PopupMenu", _box(Color(Style.EDGE, .3), Color.TRANSPARENT, 0))
	var separator := StyleBoxLine.new()
	separator.color = Style.EDGE
	separator.thickness = 1
	result.set_stylebox("separator", "HSeparator", separator)
	var track := _box(Style.EDGE, Color.TRANSPARENT, 0)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	result.set_stylebox("slider", "HSlider", track)
	var fill: StyleBoxFlat = track.duplicate()
	fill.bg_color = Style.SECTION_TEAL
	result.set_stylebox("grabber_area", "HSlider", fill)
	result.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return result

static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _box(Style.INK, Style.INK))
	button.add_theme_stylebox_override("hover", _box(Style.SECTION_TEAL, Style.SECTION_TEAL))
	button.add_theme_stylebox_override("pressed", _box(Style.SECTION_BROWN, Style.SECTION_BROWN))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, Style.PAPER)
