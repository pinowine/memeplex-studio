extends RefCounted

const CardFace := preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")

var _desk: Control

func _init(desk: Control) -> void:
	_desk = desk

func control_cursor_shape(control: Control, point: Vector2 = Vector2.INF) -> int:
	if control != null and point == Vector2.INF: point = control.get_viewport().get_mouse_position()
	var information := false
	while control != null:
		if not _contains(control, point) or control.get_meta("physical_hardware", false): return Input.CURSOR_ARROW
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			control = control.get_parent_control()
			continue
		if control is BaseButton:
			return int(control.get_meta("disabled_cursor_shape", Input.CURSOR_FORBIDDEN)) if control.disabled else _control_shape(control, Input.CURSOR_POINTING_HAND)
		if control is LineEdit or control is TextEdit:
			return Input.CURSOR_POINTING_HAND if control.editable else (Input.CURSOR_HELP if _has_help(control) else Input.CURSOR_ARROW)
		if control is Slider:
			return Input.CURSOR_POINTING_HAND if control.editable else Input.CURSOR_FORBIDDEN
		if control is ScrollBar:
			return Input.CURSOR_POINTING_HAND if control.max_value - control.min_value > control.page else Input.CURSOR_FORBIDDEN
		if control is DeskMaterialCards.StackCard: return _material_shape(control.record)
		if control is DeskEventMaterialSlip:
			return _material_shape(control.record) if control._enabled else Input.CURSOR_FORBIDDEN
		if control is DeskModulePaperClip: return Input.CURSOR_CROSS if _desk._can_focus_slot("edit") else Input.CURSOR_POINTING_HAND
		var local := control.get_global_transform_with_canvas().affine_inverse() * point
		if control is DeskContextBoard:
			if not control._layer_at(local).is_empty():
				if not control._enabled: return Input.CURSOR_FORBIDDEN
				return Input.CURSOR_CROSS if _desk._can_focus_slot("cultivate") else Input.CURSOR_POINTING_HAND
			return Input.CURSOR_ARROW
		if control is DeskNeuralSketch: return _shape(control.cursor_shape_at(local))
		if control is DeskDendriteTree:
			return control.cursor_shape_at(local)
		if control.has_method("cursor_shape_at"): return _shape(int(control.cursor_shape_at(local)))
		information = information or _has_help(control)
		if control.mouse_default_cursor_shape != Control.CURSOR_ARROW:
			var shape := _shape(control.mouse_default_cursor_shape)
			if shape != Input.CURSOR_HELP: return shape
			information = true
		if control.mouse_filter == Control.MOUSE_FILTER_STOP: break
		control = control.get_parent_control()
	return Input.CURSOR_HELP if information else Input.CURSOR_ARROW

func _control_shape(control: Control, default_shape: int) -> int:
	return default_shape if control.mouse_default_cursor_shape in [Control.CURSOR_ARROW, Control.CURSOR_HELP] else _shape(control.mouse_default_cursor_shape)

func _shape(shape: int) -> int:
	if shape in [Input.CURSOR_ARROW, Input.CURSOR_HELP, Input.CURSOR_POINTING_HAND, Input.CURSOR_CROSS, Input.CURSOR_FORBIDDEN]: return shape
	return Input.CURSOR_POINTING_HAND

func _has_help(control: Control) -> bool:
	if not control.tooltip_text.is_empty() or not control.get_meta("hover_record", {}).is_empty(): return true
	var body: Variant = control.get("help_body")
	return body is String and not body.is_empty()

func _material_shape(record: Dictionary) -> int:
	if str(record.get("kind", "")) == "module" and int(record.get("clipped_slot", -1)) < 0:
		var editor: Control = _desk._page.hud.design_workbench()
		if not editor._candidate_patch_errors(str(record.id)).is_empty(): return Input.CURSOR_FORBIDDEN
	return Input.CURSOR_POINTING_HAND

func target_at(point: Vector2) -> Dictionary:
	var cards: Control = _desk._material_cards
	var target := control_target(_desk.get_viewport().gui_get_hovered_control(), point)
	if not target.is_empty(): return target
	if cards._enabled and cards.is_visible_in_tree():
		var key := String(cards._props._hit_prop(point))
		if key.begins_with("stack/"):
			var surface: Control = cards._stack_surfaces[key.trim_prefix("stack/")]
			return _card(surface._face, key, Input.CURSOR_CROSS)
		if cards._cards.has(key):
			var card: Dictionary = cards._cards[key]
			var shape := _material_shape(card)
			if card.inventory_docked or not _desk.slot_details_active(): shape = Input.CURSOR_CROSS
			return _card(card.face, key, shape)
	var slips: Array = cards._pending_cards.values() + _desk._fax.material_slips()
	for slip: Control in slips:
		if not slip._enabled or not _contains(slip, point): continue
		return _card(slip._face, "", _material_shape(slip.record)) if slip._face != null else _rect("slip/" + str(slip.get_instance_id()), slip, Rect2(Vector2.ZERO, slip.size), _material_shape(slip.record))
	target = _inventory_target(point)
	if not target.is_empty(): return target
	if _desk._props.enabled and String(_desk._props._hit_prop(point)) in ["crt", "printer", "fax", "clock", "speed"]: return {}
	if _desk._props.enabled:
		var key := String(_desk._props._hit_prop(point))
		if key.begins_with("sheet/"):
			var note: TextureRect = _desk._stack.tab_node(key.trim_prefix("sheet/")).get_node("Note")
			var tab_target := _rect(key, note, Rect2(Vector2.ZERO, note.size), Input.CURSOR_CROSS)
			tab_target.texture = note.texture
			return tab_target
	return _fax_target(point)

func control_target(control: Control, point: Vector2 = Vector2.INF) -> Dictionary:
	if control != null and point == Vector2.INF: point = control.get_viewport().get_mouse_position()
	while control != null:
		if not _contains(control, point): return {}
		if control.get_meta("physical_hardware", false): return {}
		if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			control = control.get_parent_control()
			continue
		if control is DeskMaterialCards.StackCard:
			var scroll := control.get_parent().get_parent() as ScrollContainer
			if scroll.is_queued_for_deletion(): return {}
			var shape := _material_shape(control.record)
			var card := _rect("expanded/" + str(control.record.id), control, Rect2(Vector2.ZERO, control.size), shape) if control.token else _card(control.face, "", shape)
			var clip := _rect("", scroll, Rect2(Vector2.ZERO, scroll.size))
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(card.polygon, clip.polygon):
				if Geometry2D.is_point_in_polygon(point, polygon):
					card.polygon = polygon
					return card
			return {}
		if control is BaseButton:
			return _rect("control/" + str(control.get_instance_id()), control, Rect2(Vector2.ZERO, control.size), control_cursor_shape(control, point))
		if control is LineEdit or control is TextEdit:
			return _rect("editor/" + str(control.get_instance_id()), control, Rect2(Vector2.ZERO, control.size), Input.CURSOR_POINTING_HAND) if control.editable else {}
		if control is Slider:
			return _rect("slider/" + str(control.get_instance_id()), control, Rect2(Vector2.ZERO, control.size), Input.CURSOR_POINTING_HAND if control.editable else Input.CURSOR_FORBIDDEN)
		if control is ScrollBar:
			return _rect("scroll/" + str(control.get_instance_id()), control, Rect2(Vector2.ZERO, control.size), Input.CURSOR_POINTING_HAND if control.max_value - control.min_value > control.page else Input.CURSOR_FORBIDDEN)
		if control.mouse_filter == Control.MOUSE_FILTER_STOP: return {}
		control = control.get_parent_control()
	return {}

func _inventory_target(point: Vector2) -> Dictionary:
	var monitor: Control = _desk._monitor
	if monitor._mode == "meme": return {}
	var inventory: Control = monitor._inventory
	if not _contains(inventory, point): return {}
	var local := inventory.get_global_transform_with_canvas().affine_inverse() * point
	for index in 4:
		var id: String = inventory.IDS[inventory._mode][index]
		var rect: Rect2 = inventory.cell_rect(index)
		if rect.has_point(local):
			var enabled: bool = monitor._token_enabled and inventory._enabled and int(inventory._balances.get(id, 0)) > 0
			return _rect("inventory/" + id, inventory, rect, Input.CURSOR_POINTING_HAND if enabled else Input.CURSOR_FORBIDDEN)
	return {}

func _fax_target(point: Vector2) -> Dictionary:
	var fax: Control = _desk._fax
	if fax._blocked: return {}
	if fax._can_phone() and fax._view.book.is_visible_in_tree():
		var contacts: Control = fax._view.ruled_contacts
		var local := contacts.get_global_transform_with_canvas().affine_inverse() * point
		for row: Dictionary in contacts.inspection().rows:
			var area := Rect2(row.name_baseline - Vector2(4, 12), Vector2(contacts.size.x * .7, 14))
			if area.has_point(local): return _rect("contact/" + str(row.index), contacts, area)
	if not fax._output.continuous_output: return {}
	var paper: Control = fax._output_at(point)
	if paper == null: return {}
	var local := paper.get_global_transform_with_canvas().affine_inverse() * point
	var tab: Rect2 = paper.history_tab_rect()
	return _rect("fax_paper/" + str(paper.get_instance_id()), paper, tab if tab.has_point(local) else Rect2(Vector2.ZERO, paper.size), Input.CURSOR_CROSS)

func _card(face: Control, key: String = "", cursor_shape: int = Input.CURSOR_POINTING_HAND) -> Dictionary:
	if key.is_empty(): key = "card/" + str(face.get_instance_id())
	return _target(key, face, CardFace.outline_for(face._kind, face._layout.body), cursor_shape)

func _rect(key: String, source: Control, rect: Rect2, cursor_shape: int = Input.CURSOR_POINTING_HAND) -> Dictionary:
	return _target(key, source, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), cursor_shape)

func _target(key: String, source: Control, polygon: PackedVector2Array, cursor_shape: int = Input.CURSOR_POINTING_HAND) -> Dictionary:
	if not source.get_meta("hover_outline", true): return {}
	for mask: Control in _desk._stack._masks.values():
		if mask == source or mask.is_ancestor_of(source): return {}
	return {"key":key, "polygon":source.get_global_transform_with_canvas() * polygon, "source":source, "cursor_shape":cursor_shape}

func _contains(control: Control, point: Vector2) -> bool:
	return control.is_visible_in_tree() and Rect2(Vector2.ZERO, control.size).has_point(control.get_global_transform_with_canvas().affine_inverse() * point)
