extends RefCounted

const FONT := preload("res://assets/image/fonts/handwritten_font.tres")
const BODY_FONT := preload("res://assets/image/fonts/development_font.tres")
const MEDIUM_FONT := preload("res://assets/image/fonts/body_medium_font.tres")
const SEMIBOLD_FONT := preload("res://assets/image/fonts/body_semibold_font.tres")
const BOLD_FONT := preload("res://assets/image/fonts/body_bold_font.tres")
const HEADING_FONT := preload("res://assets/image/fonts/print_heading_font.tres")

static func apply_to(root: Node) -> void:
	var themes := {}
	if root is Control and root.theme == null:
		root.theme = Theme.new()
	_apply(root, themes)

static func _apply(node: Node, themes: Dictionary) -> void:
	if node is Control:
		var control := node as Control
		if control.theme != null and control.theme.get_type_variation_base("ReceiptHeading") == &"Label": return
		if control.theme != null:
			var key := control.theme.get_instance_id()
			if not themes.has(key):
				var paper_theme := control.theme.duplicate() as Theme
				paper_theme.default_font = BODY_FONT
				for type_name in paper_theme.get_font_type_list():
					if type_name == "TooltipLabel": continue
					for font_name in paper_theme.get_font_list(type_name):
						var font: Font = BOLD_FONT if "bold" in font_name else BODY_FONT
						if type_name in ["PrintHeading", "DemoHeading"]: font = HEADING_FONT
						elif type_name in ["Button", "OptionButton"]: font = MEDIUM_FONT
						elif type_name == "TabBar": font = SEMIBOLD_FONT
						paper_theme.set_font(font_name, type_name, font)
				themes[key] = paper_theme
			control.theme = themes[key]
		if control is RichTextLabel:
			for name in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
				control.add_theme_font_override(name, BOLD_FONT if "bold" in name else BODY_FONT)
		else:
			var font: Font = BODY_FONT
			if control is TabBar: font = FONT
			elif control is Button: font = MEDIUM_FONT
			elif bool(control.get_meta("paper_emphasis", false)) or control.theme_type_variation in ["PrintHeading", "DemoHeading"]: font = HEADING_FONT
			control.add_theme_font_override("font", font)
	for child in node.get_children(): _apply(child, themes)
