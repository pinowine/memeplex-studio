extends RefCounted

# This adapter translates desk presentation details, never gameplay commands.
var _desk: Control

func _init(desk: Control) -> void:
	_desk = desk

func prepare() -> void:
	_desk._art.phonebook.hide()
	_desk._props.unregister_prop(&"phonebook")

func paper_masks() -> Dictionary:
	return _desk._stack._masks

func initial_papers() -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for id in ["map", "edit", "cultivate", "spread"]:
		sources.append({"asset":"workpaper_" + id, "source":_desk._stack._masks[id], "size":Vector2(1.14, .740), "id":id, "curve":0})
	sources.append({"asset":"receipt_paper", "source":_desk._printer, "size":Vector2(.146, .330), "id":"receipt", "curve":1})
	sources.append({"asset":"note_strip", "source":_desk._hover_strip, "size":Vector2(.410, .074), "id":"note", "curve":0})
	return sources

func screen_sources() -> Array[Dictionary]:
	var lcd: Control = _desk._fax.screen_source()
	return [
		{"id":"crt_terminal__ScreenSurface", "source":_desk._monitor, "rect":_desk._monitor._screen_rect},
		{"id":"fax_machine__StatusScreen", "source":lcd, "rect":Rect2(Vector2.ZERO, lcd.size)}]

func date_source() -> Control:
	return _desk._clock

func button_target(asset_id: String, action: String) -> Button:
	match asset_id:
		"crt_terminal":
			var index: int = _desk._monitor.MODES.find(action)
			return _desk._monitor._buttons[index] if index >= 0 else null
		"speed_controls":
			return _desk._speed_strip._buttons[int(action)] if action.is_valid_int() and int(action) in [0, 1, 2] else null
		"fax_machine":
			return _desk._fax.action_target(action)
	return null

func activate_device(key: String) -> void:
	match key:
		"receipt_printer/feed": _desk._printer.advance(.35)
		"fax_machine/clear": _desk._fax.keypad_key("clear")

func camera_pose() -> Dictionary:
	_desk._camera.force_update_scroll()
	return {"position":_desk._camera.position, "rotation":_desk._camera.rotation, "zoom":_desk._camera.zoom}

func clock_angles() -> Vector2:
	return Vector2(_desk._clock_presenter._season.rotation, _desk._clock_presenter._day.rotation)

func handset_connected() -> bool:
	return _desk._fax.call_connected()

func output_papers() -> Array[Control]:
	return _desk._fax.output_papers()

func sheet_depth(id: String) -> int:
	return _desk._stack._layers[id].layer

func sheet_tab(id: String) -> TextureRect:
	return _desk._stack.tab_control(id).get_node("Note") as TextureRect

func sheets_switching() -> bool:
	return _desk._stack.is_switching()

func card_dragging(key: String) -> bool:
	if key == "context/drag": return _desk._page.hud.design_workbench().context_slice()._resource_dragging
	var interaction: Dictionary = _desk._material_cards._props.inspection()
	return bool(interaction.dragging) and str(interaction.pressed) == key

func material_faces() -> Array[Dictionary]:
	var faces: Array[Dictionary] = []
	var cards: Control = _desk._material_cards
	faces.append_array(cards.stack_faces())
	for key: String in cards._pending_cards:
		var slip: Control = cards._pending_cards[key]
		faces.append({"source":slip._face, "key":"pending/" + key, "owner":slip, "visible":slip.is_visible_in_tree()})
	for entry: Dictionary in _desk._fax.material_faces():
		faces.append(entry)
	for key: String in cards._cards:
		var card: Dictionary = cards._cards[key]
		faces.append({"source":card.face, "key":key, "owner":null, "visible":card.node.is_visible_in_tree()})
	var board: Control = _desk._page.hud.design_workbench().context_slice()
	if is_instance_valid(board._drag_preview):
		faces.append({"source":board._drag_preview, "key":"context/drag", "owner":null, "visible":board._drag_preview.is_visible_in_tree()})
	return faces

func material_handles_viewport_point(point: Vector2) -> bool:
	if _desk._foreground_ui_handles(point): return false
	var editor: Control = _desk._page.hud.design_workbench()
	if editor._interaction_enabled and editor._tab == "edit" and editor.module_clip_at(point) >= 0: return true
	var board: Control = editor.context_slice()
	if board._enabled and board.is_visible_in_tree():
		var local: Vector2 = board.get_global_transform_with_canvas().affine_inverse() * point
		if not board._layer_at(local).is_empty(): return true
	var cards: Control = _desk._material_cards
	if cards.handles_viewport_point(point): return true
	var slips: Array = cards._pending_cards.values() + _desk._fax.material_slips()
	for slip: Control in slips:
		if not slip.is_visible_in_tree() or slip.mouse_filter == Control.MOUSE_FILTER_IGNORE: continue
		if Rect2(Vector2.ZERO, slip.size).has_point(slip.get_global_transform_with_canvas().affine_inverse() * point):
			return true
	return false

func hovered_equipment(point: Vector2) -> String:
	var controls := {"crt_terminal":_desk._art.crt, "receipt_printer":_desk._art.printer, "fax_machine":_desk._art.fax, "desk_clock":_desk._clock, "speed_controls":_desk._speed_strip}
	for id: String in controls:
		var control: Control = controls[id]
		if Rect2(Vector2.ZERO, control.size).has_point(control.get_global_transform().affine_inverse() * point):
			return id
	return ""

func cancel_interactions() -> void:
	_desk._page.hud.design_workbench().context_slice()._cancel_input()
	_desk._monitor.cancel_drag()
	_desk._props.cancel_drag(&"studio_view_changed")
	_desk._material_cards._return_free_cards()
	_desk._fax.cancel_material_drag()

func return_overview() -> void:
	_desk.return_overview()

func sync_raster_presentation(viewport_rect: Rect2, can_interact: bool) -> void:
	var reader: Control = _desk._slot_reader
	if reader.is_visible_in_tree() and reader._viewport_rect != viewport_rect:
		reader._on_viewport_resized()
	_desk._environment.hide()
	_desk._art.phonebook.hide()
	for id in ["desk_surface", "crt", "fax", "printer", "phonebook", "clock", "speed"]:
		_desk._art[id].self_modulate.a = 0.0
	for shadow in _desk._shadows.values(): shadow.hide()
	for wire in _desk._wires.values(): wire.hide()
	for hover_id in _desk._hover:
		if str(hover_id).begins_with("sheet/"): continue
		var item: Variant = _desk._hover[hover_id]
		if item is Dictionary:
			for value in item.values():
				if value is TextureRect and value.name == "TornHover": value.hide()
	_desk._clock_presenter._season.hide()
	_desk._clock_presenter._day.hide()
	_desk._monitor._button_art.modulate.a = 0.0
	_desk._speed_strip._paper.self_modulate.a = 0.0
	for button in _desk._speed_strip._buttons: button.modulate.a = 0.0
	_desk._fax.use_physical_hardware()
	_sync_tabs(can_interact)

func _sync_tabs(can_interact: bool) -> void:
	var hovered := str(_desk._props.get("_hovered")) if can_interact else ""
	var pressed := str(_desk._props.get("_pressed")) if can_interact else ""
	for id in _desk._stack._tabs:
		var tab: Control = _desk._stack._tabs[id]
		var note := tab.get_node("Note") as TextureRect
		var title := tab.get_node("Title") as Label
		var key := "sheet/" + str(id)
		var is_pressed := key == pressed
		# The full note includes the strip glued over its own sheet's edge.
		note.position = Vector2(0, 1.5 if is_pressed else 0.0)
		note.size = tab.size
		title.position.y = 9.5 if is_pressed else 8.0
		var tint: Color = _desk._stack.TAB_PROFILES[id].tint
		note.self_modulate = tint.darkened(.08) if is_pressed else (tint.lightened(.08) if key == hovered else tint)
		if _desk._hover.has(key):
			_desk._update_hover_item(_desk._hover[key])
			_desk._hover[key].node.visible = key == hovered or is_pressed
