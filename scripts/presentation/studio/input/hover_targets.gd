extends RefCounted

const CardFace := preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")

var _desk: Control

func _init(desk: Control) -> void:
	_desk = desk

func target_at(point: Vector2) -> Dictionary:
	var cards: Control = _desk._material_cards
	var target := control_target(_desk.get_viewport().gui_get_hovered_control(), point)
	if not target.is_empty(): return target
	if cards._enabled and cards.is_visible_in_tree():
		var key := String(cards._props._hit_prop(point))
		if key.begins_with("stack/"):
			var surface: Control = cards._stack_surfaces[key.trim_prefix("stack/")]
			return _card(surface._face, key)
		if cards._cards.has(key): return _card(cards._cards[key].face, key)
	var slips: Array = cards._pending_cards.values() + _desk._fax.material_slips()
	for slip: Control in slips:
		if not slip._enabled or not _contains(slip, point): continue
		return _card(slip._face) if slip._face != null else _rect("slip/" + str(slip.get_instance_id()), slip, Rect2(Vector2.ZERO, slip.size))
	target = _inventory_target(point)
	if not target.is_empty(): return target
	if _desk._props.enabled and String(_desk._props._hit_prop(point)) in ["crt", "printer", "fax", "clock", "speed"]: return {}
	target = _workbench_target(point)
	if not target.is_empty(): return target
	for item: Control in _desk._context_layer_items.values():
		if item._enabled and _contains(item, point):
			return _target("layer/" + str(item.record.layer), item._view, item._view._quad)
	if _desk._props.enabled:
		var key := String(_desk._props._hit_prop(point))
		if key.begins_with("sheet/"):
			var note: TextureRect = _desk._stack.tab_node(key.trim_prefix("sheet/")).get_node("Note")
			var tab_target := _rect(key, note, Rect2(Vector2.ZERO, note.size))
			tab_target.texture = note.texture
			return tab_target
	target = _fax_target(point)
	if not target.is_empty(): return target
	return _map_target(point)

func control_target(control: Control, point: Vector2 = Vector2.INF) -> Dictionary:
	if control != null and point == Vector2.INF: point = control.get_viewport().get_mouse_position()
	while control != null:
		if not _contains(control, point): return {}
		if control is DeskMaterialCards.StackCard:
			var scroll := control.get_parent().get_parent() as ScrollContainer
			if scroll.is_queued_for_deletion(): return {}
			var card := _rect("expanded/" + str(control.record.id), control, Rect2(Vector2.ZERO, control.size)) if control.token else _card(control.face)
			var clip := _rect("", scroll, Rect2(Vector2.ZERO, scroll.size))
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(card.polygon, clip.polygon):
				if Geometry2D.is_point_in_polygon(point, polygon):
					card.polygon = polygon
					return card
			return {}
		if control == _desk._page.atlas.launch_marker:
			return _launch_target(control) if not control.disabled else {}
		if control is BaseButton:
			return {} if control.disabled else _rect("control/" + str(control.get_instance_id()), control, Rect2(Vector2.ZERO, control.size))
		if control is LineEdit or control is TextEdit:
			return _rect("editor/" + str(control.get_instance_id()), control, Rect2(Vector2.ZERO, control.size)) if control.editable else {}
		if control is Slider:
			return _rect("slider/" + str(control.get_instance_id()), control, Rect2(Vector2.ZERO, control.size)) if control.editable else {}
		if control is ScrollBar:
			return _rect("scroll/" + str(control.get_instance_id()), control, Rect2(Vector2.ZERO, control.size)) if control.max_value - control.min_value > control.page else {}
		if control.mouse_filter == Control.MOUSE_FILTER_STOP: return {}
		control = control.get_parent_control()
	return {}

func _workbench_target(point: Vector2) -> Dictionary:
	var editor: Control = _desk._page.hud.design_workbench()
	if not editor._interaction_enabled: return {}
	if editor._tab == "edit":
		var slot: int = editor.module_clip_at(point)
		if slot >= 0:
			var clip: Control = editor.module_clip_parent(slot)
			return _rect("module_clip/" + str(slot), clip, Rect2(Vector2.ZERO, clip.size))
		var neuron: Control = editor._neuron
		if _contains(neuron, point):
			var local := neuron.get_global_transform_with_canvas().affine_inverse() * point
			var id: String = neuron._hit_id(local)
			if id.begins_with("module:"):
				return _circle(id, neuron, neuron._module_point(int(id.trim_prefix("module:"))), 23.0)
			if id.begins_with("part:"):
				for index in neuron._nodes.size():
					if str(neuron._nodes[index].id) == id.trim_prefix("part:"):
						return _circle(id, neuron, neuron._point(index), 29.0)
			for index in mini(neuron._lineage.size(), 12):
				var center: Vector2 = neuron._lineage_point(index)
				if local.distance_to(center) <= 11.0: return _circle("variant/" + str(index), neuron, center, 11.0)
	elif editor._tab == "cultivate":
		return _context_target(editor.context_slice(), point)
	elif editor._tab == "spread":
		var tree: Control = editor._spread_tree
		if _contains(tree, point):
			var id: String = tree._hit_id(tree.get_global_transform_with_canvas().affine_inverse() * point)
			if not id.is_empty(): return _circle("skill/" + id, tree, tree._points[id], 27.0)
	return {}

func _context_target(board: Control, point: Vector2) -> Dictionary:
	if not board._enabled or not _contains(board, point): return {}
	var local := board.get_global_transform_with_canvas().affine_inverse() * point
	var layer: String = board._layer_at(local)
	if layer.is_empty(): return {}
	var layout: Dictionary = board._layout_layers[layer]
	var key := "context/" + layer
	if (layout.handle_rect as Rect2).has_point(local): return _rect(key + "/handle", board, layout.handle_rect)
	if board._attached(layer):
		if layer in ["stance", "pragmatic"]:
			var anchor: Vector2 = board._axis_point(layer)
			if layer == "stance" and not bool(board._layers()[layer].get("known", false)): anchor = board._axis_origin(layer)
			if local.distance_to(anchor) <= 13.0: return _circle(key + "/axis", board, anchor, 7.0)
		else:
			var slots: Array = board._layers()[layer].get("slots", [])
			for index in layout.slot_pickup_rects.size():
				if index < slots.size() and not slots[index].is_empty() and (layout.slot_pickup_rects[index] as Rect2).has_point(local):
					return _target(key + "/card/" + str(index), board, board._socket_outline(layer, layout.slot_rects[index]))
			var slot: int = board._slot_at(layer, local)
			if slot >= 0: return _target(key + "/slot/" + str(slot), board, board._socket_outline(layer, layout.slot_rects[slot]))
	return _target(key, board, layout.region_polygon)

func _inventory_target(point: Vector2) -> Dictionary:
	var monitor: Control = _desk._monitor
	if monitor._mode == "meme" or not monitor._token_enabled: return {}
	var inventory: Control = monitor._inventory
	if not inventory._enabled or not _contains(inventory, point): return {}
	var local := inventory.get_global_transform_with_canvas().affine_inverse() * point
	for index in 4:
		var id: String = inventory.IDS[inventory._mode][index]
		var rect: Rect2 = inventory.cell_rect(index)
		if rect.has_point(local) and int(inventory._balances.get(id, 0)) > 0:
			return _rect("inventory/" + id, inventory, rect)
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
	return _rect("fax_paper/" + str(paper.get_instance_id()), paper, tab if tab.has_point(local) else Rect2(Vector2.ZERO, paper.size))

func _map_target(point: Vector2) -> Dictionary:
	var map: Node2D = _desk._page.atlas
	if _desk._active_sheet != "map" or not _desk._props.enabled or not _contains(map.map_input, point): return {}
	var local: Vector2 = map._world_position(point)
	var country: int = map.world.country_at(local)
	if country < 0: return {}
	for ring: PackedVector2Array in map.world.territories[country].outlines:
		if Geometry2D.is_point_in_polygon(local, ring):
			var target := _rect("country/" + str(country), map.map_input, Rect2(Vector2.ZERO, map.map_input.size))
			for clipped: PackedVector2Array in Geometry2D.intersect_polygons(map.map_view_transform() * ring, target.polygon):
				if Geometry2D.is_point_in_polygon(point, clipped):
					target.polygon = clipped
					return target
	return {}

func _launch_target(marker: BaseButton) -> Dictionary:
	var breath: float = sin(marker._breath_time * TAU / marker.BREATH_PERIOD)
	var scale: float = 1.0 + marker._hover_amount * (0.018 + breath * 0.008)
	var origin: Vector2 = marker.TIP * (1.0 - scale)
	var points := PackedVector2Array([marker.TIP])
	for index in 49:
		var angle := lerpf(2.55, TAU + 0.59, float(index) / 48.0)
		points.append(origin + (marker.CENTER + Vector2.from_angle(angle) * 28.0) * scale)
	return _target("launch_confirmation", marker, points)

func _card(face: Control, key: String = "") -> Dictionary:
	if key.is_empty(): key = "card/" + str(face.get_instance_id())
	return _target(key, face, CardFace.outline_for(face._kind, face._layout.body))

func _rect(key: String, source: Control, rect: Rect2) -> Dictionary:
	return _target(key, source, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]))

func _circle(key: String, source: Control, center: Vector2, radius: float) -> Dictionary:
	var points := PackedVector2Array()
	for index in 40: points.append(center + Vector2.from_angle(float(index) * TAU / 40.0) * radius)
	return _target(key, source, points)

func _target(key: String, source: Control, polygon: PackedVector2Array) -> Dictionary:
	return {"key":key, "polygon":source.get_global_transform_with_canvas() * polygon, "source":source}

func _contains(control: Control, point: Vector2) -> bool:
	return control.is_visible_in_tree() and Rect2(Vector2.ZERO, control.size).has_point(control.get_global_transform_with_canvas().affine_inverse() * point)
