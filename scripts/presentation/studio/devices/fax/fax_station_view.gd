extends Control

signal contact_selected(index: int)
signal keypad_requested(key: String)
signal dial_requested
signal pickup_requested
signal hangup_requested
signal response_requested(index: int)
signal stamp_requested
signal close_requested

const A4_RATIO: float = 297.0 / 210.0
const KEY_ZONES := [Rect2(800,536,52,50),Rect2(871,536,52,50),Rect2(943,536,52,50),Rect2(800,600,52,50),Rect2(871,600,52,50),Rect2(943,600,52,50),Rect2(800,665,52,50),Rect2(871,665,52,50),Rect2(943,665,52,50),Rect2(800,729,52,52),Rect2(871,729,52,52),Rect2(943,729,52,52)]
const OutputPage := preload("res://scripts/presentation/studio/devices/fax/desk_fax_output_page.gd")
const REPLIES = preload("res://scripts/presentation/studio/devices/fax/fax_call_session.gd").REPLIES

var shade: ColorRect
var display: TextureRect
var sheet: Control
var paper_shadow: Panel
var paper: Panel
var body: RichTextLabel
var paper_title: Label
var paper_meta: Label
var paper_rule: Control
var seal_guide: Control
var seal: TextureRect
var seal_text: Label
var book: Panel
var book_art: TextureRect
var ruled_contacts: Control
var book_heading: Label
var contact_list: ItemList
var phone: Control
var number_label: Label
var status: Label
var dial_button: Button
var pickup_button: Button
var hangup_button: Button
var stamp_button: Button
var stamp_art: TextureRect
var identity: Panel
var portrait: TextureRect
var identity_label: Label
var conversation: RichTextLabel
var player_portrait: TextureRect
var player_fallback: Control
var player_title: Label
var player_line: Label
var reply_buttons: Array[Button] = []
var close_button: Button
var keys: Array[Button] = []
var reward_tray: Control
var output_host: Control
var paper_fibers: Control

class SealGuide extends Control:
	func _draw() -> void:
		var centre := size * 0.5
		var radius := minf(size.x,size.y) * 0.5 - 1.0
		for index in range(0,64,2):
			var a := float(index) * TAU / 64.0
			var b := float(index+1) * TAU / 64.0
			draw_line(centre+Vector2(cos(a),sin(a))*radius,centre+Vector2(cos(b),sin(b))*radius,Color("8b8878"),1.2,true)
		var font := get_theme_font("font","Label")
		var fs := 10 if radius < 22 else 12
		var text := DeskLocalization.text("收阅")
		var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
		draw_string(font,centre+Vector2(-width*0.5,font.get_ascent(fs)*0.35),text,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,Color("696b5b"))

class AuthorPortrait extends Control:
	func _draw() -> void:
		var ink := Color("a4c79e")
		draw_rect(Rect2(Vector2.ZERO,size),Color("18281f"))
		draw_circle(Vector2(size.x*0.5,size.y*0.33),size.x*0.16,ink)
		draw_polygon(PackedVector2Array([Vector2(size.x*.21,size.y*.82),Vector2(size.x*.35,size.y*.55),Vector2(size.x*.65,size.y*.55),Vector2(size.x*.79,size.y*.82)]),PackedColorArray([ink]))

class PhoneKeyInk extends Control:
	var action := ""
	var button: Button
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
		if button != null:
			button.mouse_entered.connect(queue_redraw)
			button.mouse_exited.connect(queue_redraw)
			button.button_down.connect(queue_redraw)
			button.button_up.connect(queue_redraw)
	func _draw() -> void:
		var unit := minf(size.x,size.y)
		var center := size*.5
		var ink := Color("f0dfb1") if button != null and button.is_hovered() else Color("d5cba9")
		if button != null and button.disabled: ink.a = .55
		var stroke := maxf(.7,unit*.065)
		if action == "backspace":
			var outline := PackedVector2Array()
			for point: Vector2 in [Vector2(-.40,0),Vector2(-.18,-.27),Vector2(.36,-.27),Vector2(.36,.27),Vector2(-.18,.27),Vector2(-.40,0)]: outline.append(center+point*unit)
			draw_polyline(outline,ink,stroke,true)
			draw_line(center+Vector2(-.04,-.12)*unit,center+Vector2(.18,.12)*unit,ink,stroke,true)
			draw_line(center+Vector2(-.04,.12)*unit,center+Vector2(.18,-.12)*unit,ink,stroke,true)
			return
		var receiver := PackedVector2Array()
		var angle := 0.0 if action == "hangup" else -.58
		for point: Vector2 in [Vector2(-.36,.02),Vector2(-.30,-.16),Vector2(-.14,-.23),Vector2(.14,-.23),Vector2(.30,-.16),Vector2(.36,.02)]: receiver.append(center+point.rotated(angle)*unit)
		draw_polyline(receiver,ink,stroke,true)
		for point: Vector2 in [Vector2(-.35,.02),Vector2(.35,.02)]: draw_line(center+(point+Vector2(0,-.04)).rotated(angle)*unit,center+(point+Vector2(0,.12)).rotated(angle)*unit,ink,stroke*1.4,true)
		var direction := Vector2(0,1) if action in ["answer","hangup"] else Vector2(1,-1).normalized()
		var arrow := center+Vector2(.1,.29)*unit
		draw_line(arrow-direction*unit*.16,arrow+direction*unit*.14,ink,stroke,true)
		var tip := arrow+direction*unit*.14
		draw_line(tip,tip-direction.rotated(.70)*unit*.12,ink,stroke,true)
		draw_line(tip,tip-direction.rotated(-.70)*unit*.12,ink,stroke,true)


func build() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade = ColorRect.new()
	shade.name = "FocusShade"
	shade.color = Color(0.12,0.13,0.12,0.68)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	output_host = Control.new()
	output_host.name = "ReceivedPaperStack"
	output_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(output_host)
	display = _image("FocusedMachine",self)
	paper_shadow = Panel.new()
	paper_shadow.name = "PaperShadow"
	paper_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color.TRANSPARENT
	shadow.shadow_color = Color(0,0,0,.22)
	shadow.shadow_size = 4
	shadow.shadow_offset = Vector2(2,3)
	paper_shadow.add_theme_stylebox_override("panel",shadow)
	add_child(paper_shadow)
	sheet = Control.new()
	sheet.name = "EventSheet"
	sheet.clip_contents = true
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet)
	paper = _panel("PaperSurface",sheet,Color("e7e0c9"))
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper_style := paper.get_theme_stylebox("panel") as StyleBoxFlat
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]: paper_style.set_border_width(side,0)
	paper_fibers = OutputPage.FiberSurface.new()
	paper_fibers.name = "PaperFibers"
	paper.add_child(paper_fibers)
	paper_meta = _label("SourceLine","",sheet,11)
	paper_meta.add_theme_color_override("font_color",Color("777766"))
	paper_title = _label("Headline","",sheet,22)
	paper_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paper_rule = OutputPage.PencilRule.new()
	paper_rule.name = "PrintRule"
	paper_rule.color = Color("6a6d5c")
	paper_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(paper_rule)
	body = RichTextLabel.new()
	body.name = "Intelligence"
	body.bbcode_enabled = false
	body.scroll_active = true
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_color_override("default_color",Color("292c26"))
	sheet.add_child(body)
	seal_guide = SealGuide.new()
	seal_guide.name = "SealGuide"
	seal_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(seal_guide)
	reward_tray = Control.new()
	reward_tray.name = "UncollectedRewardSlips"
	reward_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reward_tray)
	seal = _image("ReceivedSeal",sheet)
	seal_text = _label("ReceivedSealFallback","已收阅",sheet,18)
	seal_text.add_theme_color_override("font_color",Color("8c3029"))
	book = _panel("TelephoneBook",self,Color("c4bda8"))
	book_art = _image("BookAsset",book)
	ruled_contacts = preload("res://scripts/presentation/studio/paper/desk_ruled_contacts.gd").new()
	ruled_contacts.name = "RuledContacts"
	book.add_child(ruled_contacts)
	book_heading = _label("BookHeading","电话簿 / 已收录",book,14)
	contact_list = ItemList.new()
	contact_list.name = "Contacts"
	contact_list.item_selected.connect(contact_selected.emit)
	book.add_child(contact_list)
	phone = Control.new()
	phone.name = "Keypad"
	phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(phone)
	number_label = _label("Number","67#",phone,14)
	number_label.add_theme_color_override("font_color",Color("bcdf9e"))
	for index in 12:
		var key: String = ["1","2","3","4","5","6","7","8","9","#","0","backspace"][index]
		var button := _button("Key"+str(index),"退" if key == "backspace" else key,phone)
		_flat_key(button)
		button.pressed.connect(func() -> void: keypad_requested.emit(key))
		keys.append(button)
	dial_button = _button("Dial","拨",phone)
	_flat_key(dial_button)
	dial_button.pressed.connect(dial_requested.emit)
	pickup_button = _button("Pickup","接",phone)
	_flat_key(pickup_button)
	pickup_button.pressed.connect(pickup_requested.emit)
	hangup_button = _button("Hangup","挂断",phone)
	_flat_key(hangup_button)
	hangup_button.pressed.connect(hangup_requested.emit)
	identity = _panel("CallIdentity",self,Color("14271d"))
	portrait = _image("Portrait67",identity)
	identity_label = _label("Identity","67 / 助手",identity,13)
	identity_label.add_theme_color_override("font_color",Color("a4c79e"))
	conversation = RichTextLabel.new()
	conversation.name = "CallLog"
	conversation.bbcode_enabled = false
	conversation.scroll_active = true
	conversation.add_theme_color_override("default_color",Color("b8d9ac"))
	conversation.add_theme_font_size_override("normal_font_size",14)
	identity.add_child(conversation)
	player_portrait = _image("PlayerPortrait",identity)
	player_fallback = AuthorPortrait.new()
	player_fallback.name = "AnonymousAuthor"
	player_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(player_fallback)
	player_title = _label("PlayerIdentity","作者 / 你",identity,13)
	player_title.add_theme_color_override("font_color",Color("a4c79e"))
	player_line = _label("SelectedResponse","尚未选择回应。",identity,13)
	player_line.add_theme_color_override("font_color",Color("b8d9ac"))
	player_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for index in 3:
		var button := _button("Response"+str(index),str(REPLIES[index]) if index < REPLIES.size() else "",identity)
		button.add_theme_font_size_override("font_size",12)
		button.pressed.connect(func() -> void: response_requested.emit(index))
		reply_buttons.append(button)
	status = _label("Diagnostic","",self,12)
	status.add_theme_color_override("font_color",Color("e5ddc8"))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stamp_button = _button("Stamp","拿取印章",self)
	stamp_button.pressed.connect(stamp_requested.emit)
	stamp_art = _image("StampToolAsset",self)
	close_button = _button("CloseFocus","",self)
	close_button.pressed.connect(close_requested.emit)


func _flat_key(button: Button) -> void:
	button.flat = true
	var action: String = {"Dial":"dial", "Pickup":"answer", "Hangup":"hangup", "Key11":"backspace"}.get(str(button.name),"")
	if not action.is_empty():
		button.text = ""
		button.set_meta("physical_action",action)
		var icon := PhoneKeyInk.new()
		icon.name = "HanddrawnPhoneAction"
		icon.action = action
		icon.button = button
		button.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_theme_font_size_override("font_size",10)
	button.add_theme_color_override("font_color",Color("e4dcc4"))
	for state in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())

func _image(id: String, parent: Node) -> TextureRect:
	var image := TextureRect.new()
	image.name = id
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func _panel(id: String, parent: Node, color: Color) -> Panel:
	var panel := Panel.new()
	panel.name = id
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("59594b")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: style.set_border_width(side, 1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(id: String, text: String, parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.name = id
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color("252a23"))
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(id: String, text: String, parent: Node) -> Button:
	var button := Button.new()
	button.name = id
	button.text = text
	button.add_theme_font_size_override("font_size", 14)
	parent.add_child(button)
	button.tooltip_text = ""
	if parent == sheet:
		var style := load("res://scripts/presentation/studio/paper/desk_paper_style.gd")
		if style != null: style.apply_button(button)
	return button

func layout_station(frame: Dictionary, measure_mouth: Callable) -> Dictionary:
	size = frame.size
	var machine_rect: Rect2 = frame.machine_rect
	var bound_machine: TextureRect = frame.bound_machine
	var fixed_desktop: bool = frame.fixed_desktop
	var focus_mode: String = frame.focus_mode
	var focus_progress: float = frame.focus_progress
	var feed_progress: float = frame.feed_progress
	var continuous_output: bool = frame.continuous_output
	var external_details: bool = frame.external_details
	var focused: bool = frame.focused
	var has_active_event: bool = frame.has_active_event
	var has_archive: bool = frame.has_archive
	var starter_call: bool = frame.starter_call
	var paper_height := 0.0
	var seal_radius := 0.0
	var seal_center := Vector2.ZERO
	shade.position = Vector2.ZERO
	shade.size = size
	var target_width := minf(620.0,maxf(300.0,size.x*.48))
	var texture_size := display.texture.get_size() if display.texture != null else Vector2(1312,1199)
	var target_height := minf(target_width*texture_size.y/maxf(1.0,texture_size.x),maxf(220.0,size.y-248.0))
	var target := Rect2((size.x-target_width)*.5,18,target_width,target_height)
	var local_base := Rect2(machine_rect.position-global_position,machine_rect.size)
	if fixed_desktop: target = local_base
	display.position = local_base.position.lerp(target.position,focus_progress)
	display.size = local_base.size.lerp(target.size,focus_progress)
	var angle := bound_machine.get_global_transform_with_canvas().get_rotation() if is_instance_valid(bound_machine) else 0.0
	display.rotation = angle if fixed_desktop else lerpf(angle,0.0,focus_progress)
	var geometry: Dictionary = measure_mouth.call()
	var origin: Vector2 = geometry.origin
	var width: float = geometry.width
	var paper_angle: float = geometry.angle
	if focus_mode in ["paper","archive"]:
		var height := minf(680.0,maxf(240.0,size.y-64.0))
		var paper_width := minf(height/A4_RATIO,maxf(180.0,size.x-48.0))
		var paper_target := (size-Vector2(paper_width,paper_width*A4_RATIO))*.5
		if fixed_desktop: paper_target = local_base.get_center()-Vector2(paper_width,paper_width*A4_RATIO)*0.5
		origin = origin.lerp(paper_target,focus_progress)
		width = lerpf(width,paper_width,focus_progress)
		paper_angle = lerpf(paper_angle,0.0,focus_progress)
	sheet.position = origin
	sheet.rotation = paper_angle
	paper_height = width*A4_RATIO
	var visual_feed := 1.0 if focus_mode == "archive" else feed_progress
	var upward_feed := continuous_output and focus_mode not in ["paper", "archive"]
	if upward_feed: sheet.position -= Vector2(0, paper_height * visual_feed).rotated(paper_angle)
	sheet.size = Vector2(width,paper_height*visual_feed)
	paper_shadow.position = sheet.position
	paper_shadow.rotation = sheet.rotation
	paper_shadow.size = sheet.size
	# Keep one A4 sheet moving through the outlet.
	var material_offset := 0.0 if upward_feed else sheet.size.y-paper_height
	paper.position = Vector2(0,material_offset)
	paper.size = Vector2(width,paper_height)
	paper_fibers.size = paper.size
	paper_fibers.visible = continuous_output
	var large := focus_mode in ["paper","archive"] and focus_progress > .5
	var padding := 22.0 if large else 9.0
	paper_meta.position = Vector2(padding,padding+material_offset)
	paper_meta.size = Vector2(maxf(0,width-padding*2),16 if large else 12)
	paper_meta.add_theme_font_size_override("font_size",11 if large else 7)
	paper_title.position = Vector2(padding,(48 if large else 9)+material_offset)
	paper_title.size = Vector2(maxf(0,width-padding*2),64 if large else 30)
	paper_title.add_theme_font_size_override("font_size",23 if large else (11 if width >= 150 else 10))
	var body_y := 127.0 if large else 47.0
	paper_rule.position = Vector2(padding,body_y-10+material_offset)
	paper_rule.size = Vector2(maxf(0,width-padding*2),1)
	body.position = Vector2(padding,body_y+material_offset)
	body.size = Vector2(maxf(0,width-padding*2),maxf(0,paper_height-body_y-(92 if large else 48)))
	body.add_theme_font_size_override("normal_font_size",15 if large else (9 if width >= 150 else 8))
	seal_radius = 28.0 if large else minf(18.0,width*.1)
	seal_center = Vector2(width-padding-seal_radius,paper_height-padding-seal_radius)
	seal_guide.position = seal_center-Vector2.ONE*seal_radius+Vector2(0,material_offset)
	seal_guide.size = Vector2.ONE*seal_radius*2
	seal_guide.queue_redraw()
	seal.position = seal_guide.position
	seal.size = seal_guide.size
	seal_text.position = seal_guide.position+Vector2(0,seal_radius*.6)
	seal_text.add_theme_font_size_override("font_size",14 if large else 9)
	var paper_polygon := global_polygon(sheet,Rect2(Vector2.ZERO,sheet.size))
	phone.position = display.position
	phone.size = display.size
	phone.rotation = display.rotation
	if fixed_desktop and is_instance_valid(bound_machine):
		# The hidden display is not a source of pose: keys stay on the real machine.
		var machine_transform := get_global_transform_with_canvas().affine_inverse() * bound_machine.get_global_transform_with_canvas()
		phone.position = machine_transform.origin
		phone.rotation = machine_transform.get_rotation()
		phone.scale = machine_transform.get_scale()
		phone.size = bound_machine.size
	for index in keys.size(): _place_source_control(keys[index],KEY_ZONES[index], fixed_desktop)
	_place_source_control(dial_button,Rect2(1068,546,90,48), fixed_desktop)
	_place_source_control(pickup_button,Rect2(1068,607,90,51), fixed_desktop)
	_place_source_control(hangup_button,Rect2(1068,670,90,106), fixed_desktop)
	_place_source_control(number_label,Rect2(374,556,370,82), fixed_desktop)
	book.position = Vector2(20,60)
	book.size = Vector2(250,210)
	book_art.position = Vector2.ZERO
	book_art.size = book.size
	book_heading.position = Vector2(42,44) if book_art.texture != null else Vector2(10,10)
	contact_list.position = Vector2(42,75) if book_art.texture != null else Vector2(8,40)
	contact_list.size = Vector2(184,104)
	ruled_contacts.layout_book(Rect2(Vector2.ZERO,book.size))
	contact_list.hide()
	book_heading.hide()
	var dialogue_width := 720.0 if fixed_desktop else minf(980.0,maxf(420.0,size.x-36))
	var dialogue_height := 218.0 if starter_call else 180.0
	identity.position = Vector2((size.x-dialogue_width)*.5,maxf(280.0,size.y-dialogue_height-34.0))
	if fixed_desktop: identity.position = local_base.get_center()+Vector2(-dialogue_width*0.5,96)
	identity.size = Vector2(dialogue_width,dialogue_height)
	var half := dialogue_width*.5
	portrait.position = Vector2(16,16)
	portrait.size = Vector2(70,70)
	identity_label.position = Vector2(100,14)
	identity_label.size = Vector2(half-116,38)
	identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	conversation.position = Vector2(100,58)
	conversation.size = Vector2(half-118,100)
	player_portrait.position = Vector2(half+14,16)
	player_portrait.size = Vector2(60,60)
	player_fallback.position = player_portrait.position
	player_fallback.size = player_portrait.size
	player_fallback.queue_redraw()
	player_title.position = Vector2(half+86,14)
	player_title.size = Vector2(half-102,20)
	player_line.position = Vector2(half+86,42)
	player_line.size = Vector2(half-102,36)
	for index in reply_buttons.size():
		reply_buttons[index].position = Vector2(half+14,86+index*36)
		reply_buttons[index].size = Vector2(half-30,30)
	status.position = Vector2(20,size.y-28)
	status.size = Vector2(maxf(0,size.x-200),24)
	close_button.position = Vector2(size.x-154,12)
	if fixed_desktop:
		close_button.position = local_base.position+Vector2(local_base.size.x+12,0)
		status.position = identity.position+Vector2(0,dialogue_height+4)
		display.hide()
		shade.hide()
	close_button.size = Vector2(138,32)
	sheet.visible = ((has_active_event and feed_progress > 0.0) or (focused and focus_mode == "archive" and has_archive)) and focus_mode != "phone"
	if continuous_output and (focus_mode != "archive" or external_details): sheet.hide()
	paper_shadow.visible = sheet.visible
	reward_tray.position = Vector2(clampf(machine_rect.end.x+10,10,maxf(10,size.x-184)),clampf(machine_rect.end.y-80,10,maxf(10,size.y-180)))
	reward_tray.size = Vector2(180,160)
	if external_details and fixed_desktop:
		book.hide()
		identity.hide()
		status.hide()
	return {"paper_height":paper_height, "seal_radius":seal_radius, "seal_center":seal_center, "paper_polygon":paper_polygon}


func _place_source_control(control: Control, source: Rect2, fixed_desktop: bool) -> void:
	var content := content_rect(display)
	var dimensions := display.texture.get_size() if display.texture != null else Vector2(1312,1199)
	var target := Rect2(content.position+source.position*content.size/dimensions, source.size*content.size/dimensions)
	if control is Button: _fit_key_label(control,target.size)
	if control == number_label:
		var font := number_label.get_theme_font("font")
		var point_size := 14
		while point_size > 8 and (font.get_string_size(number_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,point_size).x > target.size.x - 2.0 or font.get_height(point_size) > target.size.y - .5): point_size -= 1
		number_label.add_theme_font_size_override("font_size",point_size)
	control.size = target.size
	control.position = target.position
	# Native font minimums may enlarge a key; keep its hit centre on the source key.
	if fixed_desktop: control.position += (target.size - control.size) * .5

func _fit_key_label(button: Button, available: Vector2) -> void:
	if button.text.is_empty(): return
	var font := button.get_theme_font("font","Button")
	var font_size := 12
	while font_size > 8 and (font.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x > available.x-1.0 or font.get_height(font_size) > available.y-.5): font_size -= 1
	button.add_theme_font_size_override("font_size",font_size)

static func content_rect(machine: TextureRect) -> Rect2:
	if machine.texture == null: return Rect2(Vector2.ZERO, machine.size)
	var dimensions := machine.texture.get_size()
	if machine.stretch_mode in [TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED]:
		var scale := minf(machine.size.x / maxf(1, dimensions.x), machine.size.y / maxf(1, dimensions.y))
		var scaled := dimensions * scale
		return Rect2((machine.size - scaled) * 0.5 if machine.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED else Vector2.ZERO, scaled)
	return Rect2(Vector2.ZERO, machine.size)

static func global_polygon(node: Control, rect: Rect2) -> PackedVector2Array:
	var transform := node.get_global_transform_with_canvas()
	return PackedVector2Array([transform * rect.position, transform * (rect.position + Vector2(rect.size.x, 0)), transform * rect.end, transform * (rect.position + Vector2(0, rect.size.y))])
