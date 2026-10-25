class_name DeskRuledContacts
extends Control

const ART_PATH := "res://assets/image/textures/studio/desk/phonebook.png"
const SOURCE_SIZE := Vector2(1484,1060)
const RULE_ROWS := [316.0,368.0,417.0,466.0,514.0,562.0,610.0,659.0,708.0,757.0,805.0]
const NAME_X := 280.0
const NUMBER_X := 804.0

@export var first_rule := 0
@export var source_font_size := 42.0
@export var ink := Color("34362b")
var _contacts: Array[Dictionary] = []
var _errors := PackedStringArray()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = ""
	resized.connect(queue_redraw)

func set_contacts(contacts: Array) -> void:
	_contacts.clear()
	_errors.clear()
	for index in contacts.size():
		if not contacts[index] is Dictionary:
			_errors.append("contacts[%d] must be a Dictionary" % index)
			continue
		var contact: Dictionary = contacts[index]
		var display_name := DeskLocalization.text(str(contact.get("name", ""))).strip_edges()
		var number := str(contact.get("number", "")).strip_edges()
		if display_name.is_empty() or number.is_empty():
			_errors.append("contacts[%d] needs name and number" % index)
			continue
		_contacts.append(contact.duplicate(true))
	if _contacts.size() > maxi(0,RULE_ROWS.size()-clampi(first_rule,0,RULE_ROWS.size())):
		_errors.append("%d contacts exceed %d printed rows" % [_contacts.size(),maxi(0,RULE_ROWS.size()-clampi(first_rule,0,RULE_ROWS.size()))])
	queue_redraw()

func layout_book(rect: Rect2) -> void:
	position = rect.position
	size = rect.size

func fitted_rect() -> Rect2:
	var factor := maxf(0.0,minf(size.x/SOURCE_SIZE.x,size.y/SOURCE_SIZE.y))
	return Rect2((size-SOURCE_SIZE*factor)*.5,SOURCE_SIZE*factor)

func _rows() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var fit := fitted_rect()
	var factor := fit.size.x/SOURCE_SIZE.x
	var start := clampi(first_rule,0,RULE_ROWS.size())
	for index in mini(_contacts.size(),RULE_ROWS.size()-start):
		var source_y: float = RULE_ROWS[index+start]
		var rule_y: float = fit.position.y + source_y*factor
		result.append({"index":index,"name":str(_contacts[index].name),"number":str(_contacts[index].number),
			"source_rule_y":source_y,"source_baseline":source_y,"rule_y":rule_y,"baseline":rule_y,
			"name_baseline":Vector2(fit.position.x+NAME_X*factor,rule_y),
			"number_baseline":Vector2(fit.position.x+NUMBER_X*factor,rule_y)})
	return result

func _draw() -> void:
	var factor := fitted_rect().size.x/SOURCE_SIZE.x
	if factor <= 0.0: return
	var font := get_theme_font("font")
	var font_size := maxi(1,roundi(source_font_size*factor))
	for row in _rows():
		# Canvas drawing uses the baseline, unlike a Label's top-left origin.
		draw_string(font,row.name_baseline,row.name,HORIZONTAL_ALIGNMENT_LEFT,466.0*factor,font_size,ink)
		draw_string(font,row.number_baseline,row.number,HORIZONTAL_ALIGNMENT_LEFT,468.0*factor,font_size,ink)

func inspection() -> Dictionary:
	var overflow: Array[Dictionary] = []
	for index in range(maxi(0,RULE_ROWS.size()-clampi(first_rule,0,RULE_ROWS.size())),_contacts.size()): overflow.append(_contacts[index].duplicate(true))
	var fit := fitted_rect()
	return {"component":"ruled_contacts","art_path":ART_PATH,"source_size":SOURCE_SIZE,
		"first_rule":first_rule,"fit_rect":fit,"rows":_rows(),"rule_rows":RULE_ROWS,"contacts":_contacts.duplicate(true),
		"overflow":overflow,"errors":_errors.duplicate(),"font_size":maxi(1,roundi(source_font_size*fit.size.x/SOURCE_SIZE.x)),
		"mouse_filter":mouse_filter,"tooltip_text":tooltip_text,"layout_mode":"keep_aspect_centered_source_baselines"}
