extends CanvasLayer

const MainMenu = preload("res://scripts/presentation/ui/menus/main_menu.gd")
const Tutorial = preload("res://scripts/presentation/ui/tutorial/tutorial.gd")
const Summary = preload("res://scripts/presentation/ui/summary/ending_summary.gd")

var page: Node2D
var main_menu: Control
var tutorial: Control
var ending: Control
var main_mode := true

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
			if reader != null and not reader._choice_buttons.is_empty():
				return reader._choice_buttons[0]
			return null
		"fax/hangup": return fax.action_target("hangup")
		"speed": return page.desk._speed_strip
		"desktop/machines": return page.desk._art.fax
		"editor/clips": return editor.module_clip_parent(0)
		"editor/publish": return page.hud.get_node("%Publish")
		"context/slot": return editor.context_slice()
		"spread/skill": return editor.get("_buy")
		"map/country": return page.atlas.map_input
		"map/confirm": return page.atlas.get_node("%StudioConfirm")
	if id.begins_with("sheet/"): return page.desk._stack.tab_control(id.trim_prefix("sheet/"))
	return null

func _tutorial_reserved_areas() -> Array:
	var rectangles: Array = []
	var reader: Control = page.desk._slot_reader
	if reader != null and reader.is_visible_in_tree():
		rectangles.append(reader.inspection().target_rect)
	return rectangles

func inspection() -> Dictionary:
	return {"main_mode":main_mode,"main_menu":main_menu.inspection(),"tutorial":tutorial.inspection(),"ending":ending.inspection(),"clock_paused":pauses_clock()}
