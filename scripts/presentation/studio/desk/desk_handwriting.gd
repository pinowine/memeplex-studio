extends RefCounted

const Typography = preload("res://scripts/presentation/ui/components/desk_typography.gd")

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
				Typography.apply_theme(paper_theme)
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
				var font: Font = BOLD_FONT if "bold" in name else BODY_FONT
				if control.get_theme_font(name) != font:
					control.add_theme_font_override(name, font)
		else:
			var font: Font = BODY_FONT
			if control is TabBar: font = FONT
			elif control is Button: font = MEDIUM_FONT
			elif bool(control.get_meta("paper_section_heading", false)):
				var section_font: Variant = control.get_meta("paper_section_font") if control.has_meta("paper_section_font") else null
				font = section_font if section_font is Font else SEMIBOLD_FONT
			elif bool(control.get_meta("paper_emphasis", false)) or control.theme_type_variation in ["PrintHeading", "DemoHeading"]: font = HEADING_FONT
			if control.get_theme_font("font") != font:
				control.add_theme_font_override("font", font)
		if control is Label or control is RichTextLabel:
			var size_key := "normal_font_size" if control is RichTextLabel else "font_size"
			var current_size := control.get_theme_font_size(size_key)
			if current_size <= 40:
				var role := str(control.get_meta("text_role", Typography.THEME_ROLES.get(str(control.theme_type_variation), Typography.role_for_size(current_size) if control.has_theme_font_size_override(size_key) else "body")))
				Typography.apply_control(control, role)
	for child in node.get_children(): _apply(child, themes)
