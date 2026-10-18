class_name DeskPaperStyle
extends RefCounted


class PaperFeedback extends Control:
	var button: Button
	var allow_tooltip := false
	var hover := 0.0
	var press := 0.0
	var disabled := 0.0
	var _pulse := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		show_behind_parent = true
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.pressed.connect(_on_pressed)
		button.resized.connect(queue_redraw)

	func _on_pressed() -> void:
		_pulse = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_instance_valid(button): return
		if not allow_tooltip: button.tooltip_text = ""
		var before := Vector4(hover,press,disabled,_pulse)
		var blend := 1.0 - exp(-maxf(delta,0.0) * 17.0)
		hover = lerpf(hover,1.0 if button.is_hovered() and not button.disabled else 0.0,blend)
		press = lerpf(press,1.0 if button.button_pressed and not button.disabled else _pulse * .7,blend)
		disabled = lerpf(disabled,1.0 if button.disabled else 0.0,blend)
		_pulse = move_toward(_pulse,0.0,maxf(delta,0.0) * 5.0)
		if before != Vector4(hover,press,disabled,_pulse): queue_redraw()

	func _draw() -> void:
		if size.x < 2.0 or size.y < 2.0: return
		var rect := Rect2(Vector2(2,2),size-Vector2(4,4)).grow(-press * .8)
		var color := Color("485046").lerp(Color("9d503c"),hover * .48 + press * .3)
		color.a = lerpf(.68,.25,disabled)
		draw_colored_polygon(PackedVector2Array([rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]),Color(.83,.80,.71,(.025+hover*.065+press*.045)*(1.0-disabled)))
		var corners := PackedVector2Array([rect.position+Vector2(0,.4),rect.position+Vector2(rect.size.x,-.2),rect.end+Vector2(-.4,.3),rect.position+Vector2(-.2,rect.size.y),rect.position+Vector2(0,.4)])
		draw_polyline(corners,color,.75 + press * .25,true)
		if hover > .01:
			draw_line(rect.position+Vector2(5,rect.size.y-2),rect.end-Vector2(5,1),Color(color,hover*.28),.55,true)

	func inspection() -> Dictionary:
		return {"hover":hover,"press":press,"disabled":disabled,"pulse":_pulse,"mouse_filter":mouse_filter,"allow_tooltip":allow_tooltip,"font":button.get_theme_font("font"),"style":"handdraw_paper_button"}


static func apply_button(button: Button, allow_tooltip: bool = false) -> Control:
	if button == null: return null
	var existing := button.get_node_or_null("HanddrawFeedback")
	if existing is PaperFeedback:
		existing.allow_tooltip = allow_tooltip
		button.set_meta("allow_paper_tooltip",allow_tooltip)
		if not allow_tooltip: button.tooltip_text = ""
		return existing
	for state: String in ["normal","hover","pressed","disabled","focus","hover_pressed"]:
		var original: StyleBox = button.get_theme_stylebox(state)
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = original.get_margin(SIDE_LEFT)
		empty.content_margin_top = original.get_margin(SIDE_TOP)
		empty.content_margin_right = original.get_margin(SIDE_RIGHT)
		empty.content_margin_bottom = original.get_margin(SIDE_BOTTOM)
		button.add_theme_stylebox_override(state,empty)
	if not allow_tooltip: button.tooltip_text = ""
	button.set_meta("allow_paper_tooltip",allow_tooltip)
	var feedback := PaperFeedback.new()
	feedback.name = "HanddrawFeedback"
	feedback.button = button
	feedback.allow_tooltip = allow_tooltip
	button.add_child(feedback)
	return feedback


static func apply_buttons(root: Node) -> int:
	if root == null: return 0
	var count := 0
	if root is Button:
		apply_button(root)
		count = 1
	for child: Node in root.get_children():
		if not child is PaperFeedback: count += apply_buttons(child)
	return count


static func suppress_tooltips(root: Node) -> void:
	if root == null: return
	if root is Control and not bool(root.get_meta("allow_paper_tooltip",false)):
		root.tooltip_text = ""
		if root is ItemList:
			for index in root.item_count:
				root.set_item_tooltip(index,"")
				root.set_item_tooltip_enabled(index,false)
	for child: Node in root.get_children(): suppress_tooltips(child)


static func set_tooltip_allowed(control: Control, allowed: bool = true) -> void:
	if control == null: return
	control.set_meta("allow_paper_tooltip",allowed)
	if not allowed: control.tooltip_text = ""
	if control is Button: apply_button(control,allowed)
