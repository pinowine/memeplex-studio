extends CanvasLayer

const MainMenu = preload("res://scripts/presentation/ui/menus/main_menu.gd")
const Tutorial = preload("res://scripts/presentation/ui/tutorial/tutorial.gd")
const Summary = preload("res://scripts/presentation/ui/summary/ending_summary.gd")

var page: Node2D
var main_menu: Control
var tutorial: Control
var ending: Control
var main_mode := true
var _tutorial_anchor: Control
var _tutorial_drag_source_key := ""
var _tutorial_drag_anchor: Control
var _tutorial_drag_anchor_uv := Vector2(0.5, 0.5)
var _tutorial_dragged_card: Control
var _tutorial_drag_origin := Vector2.ZERO

func configure(owner_page: Node2D) -> void:
	page = owner_page
	layer = 70
	main_menu = MainMenu.new()
	main_menu.name = "MainMenu"
	main_menu.configure({"existing_background":true,"settings_path":"user://meme_interface.cfg"})
	add_child(main_menu)
	main_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial67"
	add_child(tutorial)
	tutorial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var steps: Array[Dictionary] = tutorial.default_steps()
	tutorial.step_changed.connect(_reconcile_startup_step)
	tutorial.configure(steps, _target, _tutorial_reserved_areas, _tutorial_requires_overview)
	tutorial.set_drag_target_provider(_tutorial_drag_targets)
	tutorial.set_input_target_provider(_tutorial_input_targets, _tutorial_input_contains)
	tutorial.overview_requested.connect(page._return_to_desktop)
	page.desk._monitor.mode_changed.connect(func(id: String):
		tutorial.observe_action("monitor_mode_changed", {"mode":page.desk._monitor.MODES.find(id)}))
	tutorial.drag_cancelled.connect(_cancel_tutorial_drag)
	tutorial.finished.connect(func(skipped: bool):
		if skipped and page.desk._fax.inspection().focused: page.desk._show_component_details())
	ending = Summary.new()
	ending.name = "Ending67"
	add_child(ending)
	ending.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_menu.start_requested.connect(page._start_from_main)
	main_menu.load_requested.connect(page._load_from_main)
	main_menu.codex_requested.connect(page._open_main_codex)
	main_menu.quit_requested.connect(func(): get_tree().quit())
	ending.return_menu_requested.connect(page._return_to_main)
	show_main()

func show_main() -> void:
	main_mode = true
	tutorial.skip()
	ending.hide()
	main_menu.set_load_available(FileAccess.file_exists(page.SAVE_PATH))
	main_menu.show_menu()

func enter_game(guide: bool) -> void:
	main_mode = false
	main_menu.hide_menu()
	ending.hide()
	if guide: tutorial.begin()
	else: tutorial.skip()

func blocks_input() -> bool:
	return main_mode or main_menu.visible or ending.visible

func pauses_clock() -> bool:
	var guide: Dictionary = tutorial.inspection()
	return blocks_input() or (bool(guide.active) and str(guide.step.get("action", "")) != "speed_changed")

func observe(action: String, data: Dictionary = {}) -> void:
	tutorial.observe_action(action,data)

func _reconcile_startup_step(_id: String, step: Dictionary) -> void:
	if bool(step.get("auto_overview", false)): page._return_to_desktop()
	if _id == "starter": page.desk._show_component_details()
	if _id == "starter_confirm": _reveal_starter_confirmation()
	var action := str(step.get("action", ""))
	if action == "country_selected" and page.atlas.selected_country >= 0:
		tutorial.observe_action("country_selected", {"index":page.atlas.selected_country})
	if action not in ["phone_pickup", "starter_chosen", "startup_finished"]: return
	# These steps can be completed while the introductory notes are still open.
	# Read committed game state; completing a hint never selects or grants a draft.
	match action:
		"phone_pickup":
			var call: Dictionary = page.desk._fax.inspection()
			if page.startup_ready() or (str(call.get("number", "")) == "67#" and str(call.get("call_state", "")) == "connected"):
				tutorial.observe_action("phone_pickup")
		"starter_chosen":
			var chosen := str(page.simulation.snapshot().get("design_state", {}).get("starter_preset_id", ""))
			if not chosen.is_empty(): tutorial.observe_action("starter_chosen", {"id":chosen})
		"startup_finished":
			if page.startup_ready(): tutorial.observe_action("startup_finished")

func _reveal_starter_confirmation() -> void:
	# Selection rebuilds the paper rows; wait for the native container layout.
	await get_tree().process_frame
	if not tutorial._active or str(tutorial.inspection().step.get("id","")) != "starter_confirm": return
	var reader: Control = page.desk._slot_reader
	if reader.is_visible_in_tree() and reader._choice_buttons.size() > 3:
		reader._choice_scroll.ensure_control_visible(reader._choice_buttons[3])

func _target(id: String) -> Variant:
	var target: Variant = _logical_target(id)
	# Physical controls keep their logical nodes visible but make their ink
	# transparent. Check visibility before projection, without checking alpha.
	if target is Control and not target.is_visible_in_tree(): return null
	if page.has_meta("studio3d"):
		target = page.get_meta("studio3d").project_target(target)
	if id.begins_with("fax/option/") or id == "fax/confirm":
		var area: Rect2 = target if target is Rect2 else (target.get_global_rect() if target is Control else Rect2())
		return area.intersection(_tutorial_project_rect(page.desk._slot_reader._choice_scroll))
	return target

func _logical_target(id: String) -> Variant:
	var fax: Control = page.desk._fax
	var editor: Control = page.hud.design_workbench()
	match id:
		"fax/pickup":
			return {"hardware_key":"fax_machine/pickup"} if page.has_meta("studio3d") else fax.action_target("pickup")
		"fax/options":
			var reader: Control = page.desk._slot_reader
			if reader != null and reader.is_visible_in_tree() and not reader._choice_buttons.is_empty():
				return reader._choice_scroll
			return null
		"fax/confirm":
			var reader: Control = page.desk._slot_reader
			return reader._choice_buttons[3] if reader.is_visible_in_tree() and reader._choice_buttons.size() > 3 else null
		"fax/hangup": return fax.action_target("hangup")
		"speed": return page.desk._speed_strip
		"desktop/machines", "desktop/fax": return page.desk._art.fax
		"desktop/printer": return page.desk._art.printer
		"desktop/monitor": return page.desk._art.crt
		"desktop/note": return page.desk._hover_strip
		"desktop/clock": return page.desk._clock
		"desktop/language": return page.desk._material_cards._stack_surfaces.language
		"desktop/stacks": return _targets_bounds(["desktop/language", "desktop/stack/group", "desktop/stack/topic", "desktop/stack/module"])
		"desktop/fax_output":
			if page.has_meta("studio3d"): return {"equipment_part":"fax_machine__RearOutputSlot"}
			var mouth: Dictionary = fax._mouth_geometry()
			return _area_target(fax, Rect2(mouth.origin, Vector2(mouth.width, 18)))
		"reader/first_card":
			var grid: GridContainer = page.desk._material_cards._focus_grid
			return grid.get_child(0) if grid != null and grid.get_child_count() > 0 else null
		"reader/details": return page.desk._slot_reader._body_label
		"monitor/points": return _area_target(page.desk._monitor, page.desk._monitor._screen_rect)
		"monitor/ideology", "monitor/pragmatics": return page.desk._monitor._inventory
		"sheet/tabs": return _targets_bounds(["sheet/map", "sheet/edit", "sheet/cultivate", "sheet/spread"])
		"editor/expression": return editor._part_content
		"editor/preview": return editor._neuron
		"context/axes": return _context_regions_target(editor.context_slice(), ["stance", "pragmatic"])
		"context/layers": return _context_regions_target(editor.context_slice(), ["language", "group", "topics"])
		"spread/tree": return editor._spread_tree
		"spread/details": return editor._skill_details
		"map/details": return page.atlas.drawer
		"editor/clips":
			if not editor._pages.edit.is_visible_in_tree(): return page.desk._stack.tab_control("edit")
			var slots: Array = editor._design.get("module_slots", [])
			for index in slots.size():
				if not str(slots[index]).is_empty(): continue
				var clip: Control = editor.module_clip_parent(index)
				if clip != null: return _area_target(clip, Rect2(clip.size.x - 28, 0, 28, 48))
			return null
		"editor/publish":
			var publish: Control = page.hud.get_node("%Publish")
			return publish if publish.is_visible_in_tree() else page.desk._stack.tab_control("edit")
		"context/slot": return _context_target(editor)
		"spread/skill": return _skill_target(editor)
		"map/country": return _country_target()
		"map/confirm": return page.atlas.get_node("%StudioConfirm")
	if id.begins_with("fax/option/"):
		var buttons: Array = page.desk._slot_reader._choice_buttons
		var index := int(id.get_slice("/", 2))
		return buttons[index] if index >= 0 and index < buttons.size() else null
	if id.begins_with("desktop/stack/"): return page.desk._material_cards._stack_surfaces.get(id.get_slice("/", 2))
	if id.begins_with("monitor/button/"): return page.desk._monitor._buttons[int(id.get_slice("/", 2))]
	if id.begins_with("monitor/value/"):
		var inventory: Control = page.desk._monitor._inventory
		return _area_target(inventory, inventory.cell_rect(int(id.get_slice("/", 2))))
	if id.begins_with("sheet/"): return page.desk._stack.tab_control(id.trim_prefix("sheet/"))
	return null

func _targets_bounds(ids: Array) -> Rect2:
	var bounds := Rect2()
	for id: String in ids:
		var target: Variant = _target(id)
		var rect: Rect2 = target if target is Rect2 else (_tutorial_project_rect(target) if target is Control else Rect2())
		if rect.has_area(): bounds = bounds.merge(rect) if bounds.has_area() else rect
	return bounds

func _context_regions_target(board: Control, ids: Array) -> Control:
	var area := Rect2()
	for id: String in ids:
		var rect: Rect2 = board._layout_layers.get(id, {}).get("rect", Rect2())
		if rect.has_area(): area = area.merge(rect) if area.has_area() else rect
	return _area_target(board, area)

func _area_target(source: Control, area: Rect2) -> Control:
	if not source.is_visible_in_tree() or not area.has_area(): return null
	# Reuse a non-interactive local anchor so projection also respects paper
	# rotation and camera movement for slots that are painted, not child nodes.
	if not is_instance_valid(_tutorial_anchor):
		_tutorial_anchor = Control.new()
		_tutorial_anchor.name = "TutorialTargetAnchor"
		_tutorial_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		source.add_child(_tutorial_anchor)
	elif _tutorial_anchor.get_parent() != source:
		_tutorial_anchor.reparent(source, false)
	_tutorial_anchor.position = area.position
	_tutorial_anchor.size = area.size
	return _tutorial_anchor

func _context_target(editor: Control) -> Control:
	var board: Control = editor.context_slice()
	if not board.is_visible_in_tree(): return page.desk._stack.tab_control("cultivate")
	for resource: Dictionary in editor._design.get("resources", []):
		var target := _context_slot_target(board, str(resource.kind), str(resource.id))
		if target != null: return target
	return null

func _context_slot_target(board: Control, kind: String, id: String) -> Control:
	if kind == "topic" and int(board._resource(id).get("installed", 0)) > 0: return null
	var packet := {"type":"context_resource", "kind":kind, "resource_id":id}
	var layer_id := "topics" if kind == "topic" else kind
	for rectangle: Rect2 in board._layout_layers.get(layer_id, {}).get("slot_rects", []):
		if board._can_drop_data(rectangle.get_center(), packet):
			return _area_target(board, rectangle)
	return null

func _tutorial_drag_targets(step_id: String) -> Dictionary:
	if step_id not in ["module", "context_item"]: return {}
	var editor: Control = page.hud.design_workbench()
	if not editor._interaction_enabled: return {}
	var sheet := "edit" if step_id == "module" else "cultivate"
	if not editor._pages[sheet].is_visible_in_tree() or editor._tab != sheet: return {}
	var kinds: Array[String] = ["module"]
	if step_id == "context_item": kinds.assign(["language", "group", "topic"])
	for card: Dictionary in page.desk._material_cards.tutorial_drag_cards(kinds, _tutorial_drag_source_key, _tutorial_drag_anchor_uv):
		var target: Control = _logical_target("editor/clips") if step_id == "module" else _context_slot_target(editor.context_slice(), card.kind, card.id)
		if target == null: continue
		var source_rect := _tutorial_project_rect(card.node)
		var target_rect := _tutorial_project_rect(target)
		var viewport := get_viewport().get_visible_rect()
		if not source_rect.has_area() or not target_rect.has_area(): continue
		if not viewport.intersects(source_rect) or not viewport.intersects(target_rect): continue
		_tutorial_drag_source_key = card.key
		_tutorial_drag_anchor_uv = card.anchor
		if not is_instance_valid(_tutorial_drag_anchor):
			_tutorial_drag_anchor = Control.new()
			_tutorial_drag_anchor.name = "TutorialDragSourceAnchor"
			_tutorial_drag_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.node.add_child(_tutorial_drag_anchor)
		elif _tutorial_drag_anchor.get_parent() != card.node:
			_tutorial_drag_anchor.reparent(card.node, false)
		_tutorial_drag_anchor.size = Vector2.ONE
		_tutorial_drag_anchor.position = card.node.size * card.anchor - Vector2.ONE * 0.5
		var source_point := _tutorial_project_rect(_tutorial_drag_anchor).get_center()
		return {"source":source_rect, "source_point":source_point, "target":target_rect, "dragging":card.dragging, "kind":card.kind, "id":card.id, "accepts_point":_tutorial_drag_contains.bind(card.key)}
	return {}

func _tutorial_drag_contains(point: Vector2, key: String) -> bool:
	if page.has_meta("studio3d"): point = page.get_meta("studio3d").logical_pointer_from_root(point)
	var cards: Control = page.desk._material_cards
	if String(cards._props._hit_prop(point)) != key: return false
	_tutorial_dragged_card = cards._cards[key].node
	_tutorial_drag_origin = _tutorial_dragged_card.global_position
	return true

func _tutorial_project_rect(control: Control) -> Rect2:
	var projected: Variant = page.get_meta("studio3d").project_target(control) if page.has_meta("studio3d") else control
	if projected is Rect2: return projected
	return projected.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, projected.size)

func _cancel_tutorial_drag() -> void:
	# Keep a rejected drop on the desk so the same card remains available to retry.
	_tutorial_dragged_card.global_position = _tutorial_drag_origin

func _tutorial_input_targets(step: Dictionary) -> Array[Rect2]:
	var areas: Array[Rect2] = []
	var id := str(step.get("target", ""))
	var editor: Control = page.hud.design_workbench()
	if id in ["fax/options", "fax/confirm"]:
		if page.desk._slot_reader.is_visible_in_tree():
			areas.append(_tutorial_project_rect(page.desk._slot_reader._choice_scroll))
	elif bool(step.get("scroll", false)) and id == "desktop/printer":
		areas.append(_tutorial_project_rect(page.desk._printer))
	elif bool(step.get("map_navigation", false)) and page.atlas.map_input.is_visible_in_tree():
		areas.append(_tutorial_project_rect(page.atlas.map_input))
		if bool(step.get("allow_launch", false)) and page.atlas.launch_marker.is_visible_in_tree():
			areas.append(_tutorial_project_rect(page.atlas.launch_marker))
		if page.atlas.drawer.is_visible_in_tree(): areas.append(_tutorial_project_rect(page.atlas.drawer))
		if page.desk._revealed_focus != "sheet/map": areas.append(_tutorial_project_rect(page.desk._stack.tab_control("map")))
	elif id == "speed":
		for button: Button in page.desk._speed_strip._buttons:
			if not button.disabled: areas.append(_tutorial_project_rect(button))
	elif id == "spread/skill" and editor._spread_tree.is_visible_in_tree():
		var tree: Control = editor._spread_tree
		var unlocked: Array = editor._design.get("unlocked_skills", ["text"])
		var balance := int(editor._state.get("meme_points", 0))
		for skill: Dictionary in editor._rules.skills:
			var skill_id := str(skill.get("id", ""))
			if skill_id in unlocked or int(skill.get("cost", 0)) > balance: continue
			var available := true
			for dependency: Variant in skill.get("requires", []):
				if str(dependency) not in unlocked: available = false
			if available and tree._points.has(skill_id):
				areas.append(_tutorial_project_rect(_area_target(tree, Rect2(tree._points[skill_id] - Vector2(22, 22), Vector2(44, 44)))))
		if editor._buy.is_visible_in_tree() and not editor._buy.disabled:
			areas.append(_tutorial_project_rect(editor._buy))
	else:
		var target: Variant = _target(id)
		if target is Rect2: areas.append(target)
		elif target is Control: areas.append(_tutorial_project_rect(target))
	return areas

func _tutorial_input_contains(step: Dictionary, point: Vector2) -> bool:
	if not bool(step.get("map_navigation", false)): return true
	var marker: Control = page.atlas.launch_marker
	if marker.is_visible_in_tree() and _tutorial_project_rect(marker).has_point(point):
		return bool(step.get("allow_launch", false))
	if page.atlas.drawer.is_visible_in_tree() and _tutorial_project_rect(page.atlas.drawer).has_point(point): return true
	if page.desk._revealed_focus != "sheet/map" and _tutorial_project_rect(page.desk._stack.tab_control("map")).has_point(point): return true
	if page.has_meta("studio3d"): point = page.get_meta("studio3d").logical_pointer_from_root(point)
	var desk: Control = page.desk
	return desk._props._hit_prop(point) == &"" and not desk._material_cards.handles_viewport_point(point)

func _skill_target(editor: Control) -> Control:
	var tree: Control = editor._spread_tree
	if not tree.is_visible_in_tree(): return page.desk._stack.tab_control("spread")
	var buy: Button = editor._buy
	if buy.is_visible_in_tree() and not buy.disabled: return buy
	var unlocked: Array = editor._design.get("unlocked_skills", ["text"])
	var balance := int(editor._state.get("meme_points", 0))
	for skill: Dictionary in editor._rules.skills:
		var id := str(skill.get("id", ""))
		if id in unlocked or int(skill.get("cost", 0)) > balance: continue
		var available := true
		for dependency: Variant in skill.get("requires", []):
			if str(dependency) not in unlocked: available = false
		if available and tree._points.has(id):
			return _area_target(tree, Rect2(tree._points[id] - Vector2(22, 22), Vector2(44, 44)))
	return null

func _country_target() -> Control:
	var atlas: Node2D = page.atlas
	if not atlas.map_input.is_visible_in_tree(): return page.desk._stack.tab_control("map")
	if atlas.selected_country < 0: return null
	# Point only at the player's current choice; navigation never chooses a country.
	var point: Vector2 = atlas._local_map_view() * atlas.world.territories[atlas.selected_country].anchor
	return _area_target(atlas.map_input, Rect2(point - Vector2(20, 20), Vector2(40, 40)))

func _tutorial_reserved_areas() -> Array:
	var rectangles: Array = []
	if page.atlas.drawer.is_visible_in_tree():
		rectangles.append(_tutorial_project_rect(page.atlas.drawer))
	var reader: Control = page.desk._slot_reader
	if reader != null and reader.is_visible_in_tree():
		rectangles.append(reader.inspection().target_rect)
	return rectangles

func _tutorial_requires_overview(target_id: String) -> bool:
	if not target_id.begins_with("desktop/") and target_id != "speed": return false
	var camera: Dictionary = page.desk._camera.inspection()
	if target_id == "speed" and str(camera.target) == "speed": return false
	return str(camera.state) in ["focused", "travelling"]

func hover_starter(index: int) -> void:
	if not bool(page.desk._slot_reader._details.get("starter_pending", false)): return
	if index < 0 or index >= 3:
		tutorial.clear_hover()
		return
	var id := str(page.desk._slot_reader._details.options[index].id)
	var comments := {"case_s01":"LOC_OPENING_HOVER_FINE", "case_s16":"LOC_OPENING_HOVER_PEAK", "case_p11":"LOC_OPENING_HOVER_67"}
	tutorial.set_hover("fax/option/%d" % index, str(comments.get(id, "")))

func _process(_delta: float) -> void:
	if tutorial == null or not tutorial._active: return
	var target := str(tutorial._steps[tutorial._index].get("target", ""))
	if target not in ["monitor/ideology", "monitor/pragmatics"]: return
	var point := tutorial.get_viewport().get_mouse_position()
	for index in 4:
		var value: Variant = _target("monitor/value/%d" % index)
		var rect: Rect2 = value if value is Rect2 else (_tutorial_project_rect(value) if value is Control else Rect2())
		if rect.has_point(point):
			tutorial.set_hover("monitor/value/%d" % index, page.desk._monitor.mentor_comment_key(index))
			return
	tutorial.clear_hover()

func inspection() -> Dictionary:
	return {"main_mode":main_mode,"main_menu":main_menu.inspection(),"tutorial":tutorial.inspection(),"ending":ending.inspection(),"clock_paused":pauses_clock()}
