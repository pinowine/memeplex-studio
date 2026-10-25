extends RefCounted

const FONT := preload("res://assets/image/fonts/handwritten_font.tres")

static func apply_to(root: Node) -> void:
	var themes := {}
	if root is Control and root.theme == null:
		root.theme = Theme.new()
	_apply(root, themes)

static func _apply(node: Node, themes: Dictionary) -> void:
	if node is Control:
		var control := node as Control
		if control.theme != null:
			var key := control.theme.get_instance_id()
			if not themes.has(key):
				var paper_theme := control.theme.duplicate() as Theme
				paper_theme.default_font = FONT
				# Headings and custom type variations must not keep a printed font.
				for type_name in paper_theme.get_font_type_list():
					for font_name in paper_theme.get_font_list(type_name):
						paper_theme.set_font(font_name, type_name, FONT)
				themes[key] = paper_theme
			control.theme = themes[key]
		if control is RichTextLabel:
			for name in ["normal_font", "bold_font", "italics_font", "bold_italics_font", "mono_font"]:
				control.add_theme_font_override(name, FONT)
		else:
			control.add_theme_font_override("font", FONT)
	for child in node.get_children(): _apply(child, themes)
