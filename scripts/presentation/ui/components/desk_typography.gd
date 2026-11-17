extends RefCounted

const BODY_FONT = preload("res://assets/image/fonts/development_font.tres")
const MEDIUM_FONT = preload("res://assets/image/fonts/body_medium_font.tres")
const SEMIBOLD_FONT = preload("res://assets/image/fonts/body_semibold_font.tres")
const BOLD_FONT = preload("res://assets/image/fonts/body_bold_font.tres")
const HEADING_FONT = preload("res://assets/image/fonts/print_heading_font.tres")
const INK := Color("3f4338")
const MUTED := Color("68604f")
const ACCENT := Color("41675f")
const ROLES := {
 "title": {"size":32, "font":"heading", "weight":600, "color":INK, "tracking":0, "gap":16, "line_gap":6, "paragraph_gap":12},
 "subtitle": {"size":24, "font":"bold", "weight":700, "color":INK, "tracking":0, "gap":12, "line_gap":4, "paragraph_gap":10},
 "section": {"size":20, "font":"semibold", "weight":600, "color":INK, "tracking":0, "gap":8, "line_gap":4, "paragraph_gap":8},
 "body": {"size":14, "font":"body", "weight":400, "color":INK, "tracking":0, "gap":8, "line_gap":4, "paragraph_gap":8},
 "quote": {"size":12, "font":"body", "weight":400, "color":MUTED, "tracking":0, "gap":6, "line_gap":2, "paragraph_gap":6},
 "reference": {"size":10, "font":"medium", "weight":500, "color":ACCENT, "tracking":0, "gap":4, "line_gap":2, "paragraph_gap":4},
 "important": {"size":14, "font":"semibold", "weight":600, "color":ACCENT, "tracking":0, "gap":8, "line_gap":4, "paragraph_gap":8},
 "table_header": {"size":12, "font":"medium", "weight":500, "color":MUTED, "tracking":0, "gap":6, "line_gap":2, "paragraph_gap":4},
 "hint": {"size":12, "font":"body", "weight":400, "color":MUTED, "tracking":0, "gap":6, "line_gap":2, "paragraph_gap":6},
 "annotation": {"size":10, "font":"body", "weight":400, "color":MUTED, "tracking":0, "gap":4, "line_gap":2, "paragraph_gap":4},
 "special": {"size":14, "font":"medium", "weight":500, "color":ACCENT, "tracking":0, "gap":4, "line_gap":2, "paragraph_gap":4},
 "label": {"size":12, "font":"medium", "weight":500, "color":INK, "tracking":0, "gap":4, "line_gap":2, "paragraph_gap":4},
 "decoration": {"size":8, "font":"body", "weight":400, "color":MUTED, "tracking":0, "gap":4, "line_gap":0, "paragraph_gap":0}
}
const THEME_ROLES := {"DemoHeading":"subtitle", "PrintHeading":"subtitle", "ReceiptHeading":"subtitle", "DemoCaption":"reference", "PrintCaption":"reference"}

static func font(role: String) -> Font:
 match str(ROLES[role].font):
  "heading": return HEADING_FONT
  "bold": return BOLD_FONT
  "semibold": return SEMIBOLD_FONT
  "medium": return MEDIUM_FONT
 return BODY_FONT

static func point_size(role: String) -> int:
 return int(ROLES[role].size)

static func role_for_size(value: int) -> String:
 if value > 40: return "special"
 if value >= 29: return "title"
 if value >= 22: return "subtitle"
 if value >= 18: return "section"
 if value >= 15: return "body"
 if value >= 13: return "label"
 if value >= 11: return "reference"
 return "decoration"

static func normalized_size(value: int) -> int:
 return value if value > 40 else point_size(role_for_size(value))

static func apply_control(control: Control, role: String, preserve_ink: bool = false) -> void:
 control.set_meta("text_role", role)
 var spec: Dictionary = ROLES[role]
 if control is RichTextLabel:
  control.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
  control.add_theme_font_override("normal_font", font(role))
  control.add_theme_font_override("italics_font", font(role))
  control.add_theme_font_override("bold_font", SEMIBOLD_FONT)
  control.add_theme_font_override("bold_italics_font", SEMIBOLD_FONT)
  for key: String in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
   control.add_theme_font_size_override(key, int(spec.size))
  control.add_theme_constant_override("line_separation", int(spec.line_gap))
  control.add_theme_constant_override("paragraph_separation", int(spec.paragraph_gap))
  if not preserve_ink: control.add_theme_color_override("default_color", spec.color)
 else:
  if control is Label and control.autowrap_mode != TextServer.AUTOWRAP_OFF:
   control.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
  control.add_theme_font_override("font", font(role))
  control.add_theme_font_size_override("font_size", int(spec.size))
  control.add_theme_constant_override("line_spacing", int(spec.line_gap))
  if not preserve_ink: control.add_theme_color_override("font_color", spec.color)

static func apply_theme(theme: Theme) -> void:
 theme.default_font = BODY_FONT
 theme.default_font_size = point_size("body")
 for type: String in ["Label", "LineEdit", "TextEdit", "ItemList"]:
  theme.set_font("font", type, BODY_FONT)
  theme.set_font_size("font_size", type, point_size("body"))
  theme.set_color("font_color", type, INK)
 for type: String in ["Button", "OptionButton", "CheckButton", "CheckBox", "TabBar", "PopupMenu", "Tree"]:
  theme.set_font_size("font_size", type, point_size("body"))
 theme.set_font_size("font_size", "TooltipLabel", point_size("label"))
 theme.set_color("default_color", "RichTextLabel", INK)
 for key: String in ["normal_font", "italics_font", "mono_font"]: theme.set_font(key, "RichTextLabel", BODY_FONT)
 for key: String in ["bold_font", "bold_italics_font"]: theme.set_font(key, "RichTextLabel", SEMIBOLD_FONT)
 for key: String in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]: theme.set_font_size(key, "RichTextLabel", point_size("body"))
 theme.set_constant("line_separation", "RichTextLabel", int(ROLES.body.line_gap))
 theme.set_constant("paragraph_separation", "RichTextLabel", int(ROLES.body.paragraph_gap))
 for role: String in ROLES:
  var type := "Text" + role.to_pascal_case()
  theme.set_type_variation(type, "Label")
  theme.set_font("font", type, font(role))
  theme.set_font_size("font_size", type, point_size(role))
  theme.set_color("font_color", type, ROLES[role].color)
  theme.set_constant("line_spacing", type, int(ROLES[role].line_gap))
 for type: String in THEME_ROLES:
  var role: String = THEME_ROLES[type]
  theme.set_type_variation(type, "Label")
  theme.set_font("font", type, font(role))
  theme.set_font_size("font_size", type, point_size(role))
  theme.set_color("font_color", type, ROLES[role].color)
