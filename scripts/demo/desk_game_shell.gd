extends CanvasLayer

const MainMenu = preload("res://scripts/demo/desk_main_menu.gd")
const Tutorial = preload("res://scripts/demo/desk_tutorial.gd")
const Summary = preload("res://scripts/demo/ending_summary.gd")

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
	main_menu.configure({"existing_background":true})
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
	tutorial.configure(steps, _target)
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

func _target(id: String) -> Variant:
	var fax: Control = page.desk._fax
	var editor: Control = page.hud.design_workbench()
	match id:
		"fax/pickup": return fax.get("_pickup_button")
		"fax/options": return fax.get("_reply_buttons")[0]
		"fax/hangup": return fax.get("_hangup_button")
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

func inspection() -> Dictionary:
	return {"main_mode":main_mode,"main_menu":main_menu.inspection(),"tutorial":tutorial.inspection(),"ending":ending.inspection(),"clock_paused":pauses_clock()}
