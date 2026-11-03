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
	var speed: Dictionary = {}
	for index in range(steps.size()-1,-1,-1):
		if str(steps[index].id) == "speed": speed = steps.pop_at(index)
	steps.append(speed)
	tutorial.step_changed.connect(_reconcile_startup_step)
	tutorial.configure(steps, _target, _tutorial_reserved_areas)
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
	return blocks_input() or bool(tutorial.inspection().active)

func observe(action: String, data: Dictionary = {}) -> void:
	tutorial.observe_action(action,data)

func _reconcile_startup_step(_id: String, step: Dictionary) -> void:
	var action := str(step.get("action", ""))
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

func _target(id: String) -> Variant:
	var target: Variant = _logical_target(id)
	# Physical controls keep their logical nodes visible but make their ink
	# transparent. Check visibility before projection, without checking alpha.
	if target is Control and not target.is_visible_in_tree(): return null
	if page.has_meta("studio3d"):
		return page.get_meta("studio3d").project_target(target)
	return target

func _logical_target(id: String) -> Variant:
	var fax: Control = page.desk._fax
	var editor: Control = page.hud.design_workbench()
	match id:
		"fax/pickup": return fax.action_target("pickup")
		"fax/options":
			var reader: Control = page.desk._slot_reader
			if reader != null and reader.is_visible_in_tree() and not reader._choice_buttons.is_empty():
				return reader._choice_box
			return null
		"fax/hangup": return fax.action_target("hangup")
		"speed": return page.desk._speed_strip
		"desktop/machines", "desktop/fax": return page.desk._art.fax
		"desktop/printer": return page.desk._art.printer
		"desktop/monitor": return page.desk._art.crt
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
	if id.begins_with("sheet/"): return page.desk._stack.tab_control(id.trim_prefix("sheet/"))
	return null

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
	var state: Dictionary = editor._design
	var resources: Array = state.get("resources", [])
	for layer: String in ["language", "group", "topics"]:
		var data: Dictionary = state.get("context_layers", {}).get(layer, {})
		if not bool(data.get("attached", true)): continue
		var kind := "topic" if layer == "topics" else layer
		var available := false
		for resource: Dictionary in resources:
			if layer == "topics" and int(resource.get("installed", 0)) > 0: continue
			if str(resource.get("kind", "")) == kind and int(resource.get("available", 0)) > 0:
				available = true
				break
		if not available: continue
		var slots: Array = data.get("slots", [])
		var rectangles: Array = board._layout_layers.get(layer, {}).get("slot_rects", [])
		for index in mini(slots.size(), rectangles.size()):
			if slots[index].is_empty(): return _area_target(board, rectangles[index])
	return null

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
	var map: Control = atlas.map_input
	if not map.is_visible_in_tree(): return page.desk._stack.tab_control("map")
	var bounds := Rect2(Vector2.ZERO, map.size).grow(-24)
	var point := Vector2.ZERO
	var best_score := INF
	for index in atlas.settings.countries.size():
		var marker: Node2D = atlas.markers.get_node(str(atlas.settings.countries[index].id))
		if not bounds.has_point(marker.position): continue
		if not atlas.world.territories[index].contains(marker.anchor): continue
		var score := marker.position.distance_squared_to(bounds.get_center())
		if index == atlas.selected_country: score = -1.0
		if score < best_score:
			best_score = score
			point = marker.position
	# An interior land anchor illustrates the map interaction without selecting
	# a country or suggesting that the entire sheet must remain unobscured.
	return null if is_inf(best_score) else _area_target(map, Rect2(point - Vector2(20, 20), Vector2(40, 40)))

func _tutorial_reserved_areas() -> Array:
	var rectangles: Array = []
	var reader: Control = page.desk._slot_reader
	if reader != null and reader.is_visible_in_tree():
		rectangles.append(reader.inspection().target_rect)
	return rectangles

func inspection() -> Dictionary:
	return {"main_mode":main_mode,"main_menu":main_menu.inspection(),"tutorial":tutorial.inspection(),"ending":ending.inspection(),"clock_paused":pauses_clock()}
