extends Node2D

const SAVE_PATH := "res://demo_saves/current_run.json"
const EDITED_CATALOG := "res://content/demo/catalog.edited.tres"

@onready var atlas: Node2D = $Atlas
@onready var hud: Control = $DemoLayer/HUD
@onready var tools: PanelContainer = $ToolLayer/EventPoolEditor
@onready var spread: Control = $SpreadLayer/SpreadOverlay
@onready var desk: Control = $DeskLayer/Desk

var catalog: MemeDemoCatalog
var simulation: MemeDemoSimulation
var store := MemeDemoStore.new()
var _clock_anchor: float = 0.0
var _map_seed: int = 0
var _tool_speed: int = 0
var _menu_resume_speed: int = 0
var _ready_to_run := false
var _pending_start_draft: Dictionary = {}
var _pending_read_id: String = ""
var _startup_complete: bool = false
var _shell: CanvasLayer
var _tutorial_country := -1

func _ready() -> void:
	set_process(false)
	atlas.process_priority = 20
	if not _load_catalog(): return
	simulation = MemeDemoSimulation.new(catalog)
	simulation.changed.connect(_render)
	simulation.event_raised.connect(_on_event)
	simulation.completed.connect(_complete_run)
	hud.configure(catalog)
	tools.configure(catalog)
	hud.draft_publish_requested.connect(_publish)
	hud.country_selection_requested.connect(_choose_country)
	hud.speed_requested.connect(_set_speed)
	hud.step_requested.connect(_step)
	hud.workbench_requested.connect(_open_workbench)
	hud.tools_requested.connect(_open_tools)
	hud.save_requested.connect(_save)
	hud.load_requested.connect(_load)
	hud.restart_requested.connect(_restart)
	hud.event_acknowledged.connect(_acknowledge)
	hud.settings_requested.connect(func(): _toggle_menu("settings"))
	hud.developer_requested.connect(func(): _toggle_menu("developer"))
	hud.codex_requested.connect(func(): _toggle_menu("codex"))
	hud.quit_requested.connect(func(): get_tree().quit())
	hud.menu_close_requested.connect(_close_menu)
	hud.design_action_requested.connect(_design_action)
	hud.skill_purchase_requested.connect(_buy_skill)
	tools.closed.connect(_close_tools)
	atlas.get_node("%PointsButton").hide()
	atlas.set_process_input(false)
	# Route studio confirmation through this page's startup flow.
	var confirm: Button = atlas.get_node("%StudioConfirm")
	confirm.pressed.disconnect(atlas.establish_studio)
	confirm.pressed.connect(_studio_selected)
	atlas.get_node("%SpeedControl").pressed.connect(func(): _set_speed(atlas.clock.speed))
	# Wait for Atlas geometry before configuring the desk.
	while atlas.world == null:
		await get_tree().process_frame
	_map_seed = atlas.world.seed_value
	_clock_anchor = atlas.clock.utc_seconds
	desk.configure(self)
	spread.configure(atlas)
	hud.layout_for_date(desk.clock_rect())
	_ready_to_run = true
	desk._fax.starter_selected.connect(_select_starter)
	desk._fax.startup_finished.connect(_finish_startup)
	if not _bind_world(): return
	_shell = preload("res://scripts/demo/desk_game_shell.gd").new()
	_shell.name = "GameShell"
	add_child(_shell)
	_shell.configure(self)
	desk._fax.call_changed.connect(func(record: Dictionary):
		if str(record.get("kind", "")) == "connected": _tutorial_observe("phone_pickup"))
	_render()
	set_process(true)
	print("MEME_DEMO_READY content=%d events=%d groups=%d kernels=%d" % [catalog.content_version, catalog.events.size(), catalog.groups.size(), catalog.kernels.size()])

func _load_catalog() -> bool:
	var path := EDITED_CATALOG if FileAccess.file_exists(EDITED_CATALOG) else "res://content/demo/catalog.tres"
	var candidate := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as MemeDemoCatalog
	if candidate == null:
		_catalog_error("Cannot load demo catalog: " + path)
		return false
	var errors := candidate.validate()
	if not errors.is_empty():
		_catalog_error("Invalid demo catalog: " + "; ".join(errors))
		return false
	catalog = candidate
	return true

func _catalog_error(message: String) -> void:
	push_error(message)
	if simulation != null:
		simulation.status = message
		_render()
	else:
		hud.get_node("%Status").text = message

func _process(delta: float) -> void:
	if not _ready_to_run: return
	if not _pending_read_id.is_empty() and not tools.visible and hud.menu_mode().is_empty():
		_read_intelligence(_pending_read_id)
	atlas.workbench.hide()
	if atlas.world.seed_value != _map_seed:
		_map_seed = atlas.world.seed_value
		_pending_start_draft.clear()
		simulation.reset(simulation.seed_value + 1)
		if not _bind_world(): return
		simulation.bind_country("", "未选择投放国家")
		_clock_anchor = atlas.clock.utc_seconds
		_begin_startup()
	_sync_setup()
	if _setup_stage() == "country" and atlas.selected_country >= 0 and atlas.selected_country != _tutorial_country:
		_tutorial_country = atlas.selected_country
		_tutorial_observe("country_selected", {"index":atlas.selected_country})
	if _shell != null: _shell.tutorial.set_interaction_blocked(tools.visible or hud.modal_visible())
	if simulation.phase != "running" or _interface_paused() or hud.get_node("%Workbench").visible or hud.modal_visible() or (_shell != null and _shell.pauses_clock()):
		atlas.set_speed(0)
	elif simulation.gameplay_mode() == "world_competition":
		simulation.advance_active_seconds(delta)
		atlas.clock.utc_seconds = _clock_anchor + simulation.hour * 3600.0
		atlas._update_clock()
		atlas.set_speed(simulation.speed if simulation.phase == "running" else 0)
	else:
		# Keep the original clock progression for legacy saves.
		if atlas.clock.speed != simulation.speed:
			simulation.set_speed(atlas.clock.speed)
		while atlas.clock.utc_seconds - _clock_anchor >= (simulation.hour + 1) * 3600.0 and simulation.phase == "running":
			simulation.step_hour()
			if simulation.phase != "running":
				atlas.clock.utc_seconds = _clock_anchor + simulation.hour * 3600.0
				atlas.set_speed(0)
	atlas.get_node("%PointsValue").text = str(simulation.economy.balance)
	atlas.get_node("%PointsIncome").text = "创作资源 · 不可购买"
	hud.layout_for_date(desk.clock_rect())
	if atlas.selected_country >= 0:
		atlas.events.text = "收到 %d 条消息。" % simulation.events.size()
		atlas.competitors.text = "外面的新表达也在争取人们的目光。"

func _studio_selected() -> void:
	if not _ready_to_run or not startup_ready() or _interface_paused() or _pending_start_draft.is_empty() or simulation.publish_count != 0: return
	var index: int = atlas.selected_country
	if index < 0 or index >= atlas.settings.countries.size():
		simulation.status = "请先在地图选择投放国家，再确认进入游戏。"
		_render()
		return
	var errors := _draft_errors(_pending_start_draft)
	if not errors.is_empty():
		simulation.status = "；".join(errors)
		_render()
		return
	if _commit_draft(_pending_start_draft, index):
		_pending_start_draft.clear()
		_render()

func _bind_country(index: int) -> void:
	var country: Resource = atlas.settings.countries[index]
	simulation.bind_country(str(country.id), tr(country.short_name_key))

func _publish(draft: Dictionary) -> void:
	if not _ready_to_run or _interface_paused(): return
	if not startup_ready():
		simulation.status = "请先接听 67 来电，选择起始模因并结束通话。"
		_render()
		return
	# Turning a page is presentation only; a new version starts at explicit publish.
	var revision_view: bool = simulation.publish_count > 0 and simulation.phase in ["running", "complete"] and hud.get_node("%Workbench").visible
	var errors := _draft_errors(draft, revision_view)
	if not errors.is_empty():
		simulation.status = "；".join(errors)
		_render()
		return
	if revision_view:
		var revision_errors := simulation.begin_revision(draft)
		if not revision_errors.is_empty():
			hud.report_design_errors(revision_errors)
			return
		draft = simulation.latest_draft.duplicate(true)
		hud.set_draft(draft)
	if simulation.publish_count == 0:
		# Freeze the expression before asking for its deployment location.
		_pending_start_draft = draft.duplicate(true)
		_tutorial_country = -1
		_tutorial_observe("publish_requested")
		atlas.close_drawer()
		simulation.bind_country("", "未选择投放国家")
		simulation.status = "稿子已准备好。选一处地方，让它开始流传。"
		hud.show_workbench(false)
		_render()
		return
	var index: int = atlas.selected_country if atlas.selected_country >= 0 else atlas.clock.studio_index
	_commit_draft(draft, index)

func _draft_errors(draft: Dictionary, revision_view: bool = false) -> PackedStringArray:
	var errors := simulation.validate_draft(draft)
	if simulation.phase != "draft" and not revision_view: errors.append("请先返回创作台，建立自己的新版本。")
	var cost: int = catalog.first_publish_cost if simulation.publish_count == 0 else catalog.revision_publish_cost
	if simulation.economy.balance < cost:
		errors.append("Meme 点数不足：需要 %d，当前 %d。" % [cost, simulation.economy.balance])
	return errors

func _commit_draft(draft: Dictionary, index: int) -> bool:
	if index < 0 or index >= atlas.settings.countries.size():
		simulation.status = "请先在地图选择投放国家。"
		_render()
		return false
	var old_id := simulation.country_id
	var old_title := simulation.country_title
	_bind_country(index)
	if not simulation.publish(draft).is_empty():
		simulation.bind_country(old_id, old_title)
		return false
	if atlas.clock.studio_index != index:
		atlas.select_country(index)
		atlas.establish_studio()
		atlas.clock.utc_seconds += simulation.hour * 3600.0
		atlas._update_clock()
	_clock_anchor = atlas.clock.utc_seconds - simulation.hour * 3600.0
	hud.show_workbench(false)
	atlas.close_drawer()
	atlas.set_speed(simulation.speed)
	_tutorial_observe("published")
	_render()
	return true

func _choose_country() -> void:
	if not _ready_to_run or _interface_paused(): return
	if simulation.publish_count == 0:
		_publish(hud.get_draft())
	else:
		hud.show_workbench(false)

func _setup_stage() -> String:
	if not startup_ready(): return "starter_call"
	if simulation.publish_count == 0: return "meme" if _pending_start_draft.is_empty() else "country"
	if simulation.phase == "draft": return "revision"
	return "playing" if simulation.phase == "running" else simulation.phase

func _sync_setup() -> void:
	var stage := _setup_stage()
	hud.set_setup_stage(stage)
	atlas.map_input.mouse_filter = Control.MOUSE_FILTER_IGNORE if stage in ["starter_call", "meme"] or hud.get_node("%Workbench").visible else Control.MOUSE_FILTER_STOP
	atlas.setup_note.visible = stage == "country" and not _interface_paused() and not hud.get_node("%Workbench").visible
	atlas.get_node("%StudioConfirm").text = "投放并进入游戏"
	atlas.get_node("%StudioConfirm").disabled = stage != "country" or _interface_paused() or atlas.selected_country < 0
	atlas.setup_note.get_node("Content/Prompt").text = "选一处地方 · 投放这份稿子并开始游戏"

func _set_speed(value: int, restore_intent: bool = false) -> void:
	if _interface_paused() or hud.modal_visible():
		if restore_intent and simulation.phase == "running": simulation.set_speed(value)
		atlas.set_speed(0)
		return
	if hud.get_node("%Workbench").visible:
		if restore_intent: simulation.set_speed(value)
		atlas.set_speed(0)
		return
	simulation.set_speed(value)
	atlas.set_speed(simulation.speed)
	if simulation.phase == "running" and simulation.speed == value: _tutorial_observe("speed_changed", {"speed":value})

func _step() -> void:
	if _interface_paused() or hud.modal_visible() or hud.get_node("%Workbench").visible: return
	simulation.set_speed(0)
	atlas.set_speed(0)
	if simulation.step_hour():
		atlas.clock.utc_seconds = _clock_anchor + simulation.hour * 3600.0
		atlas._update_clock()

func _open_workbench() -> void:
	if not _ready_to_run or _interface_paused(): return
	if not startup_ready():
		desk._fax.focus()
		return
	atlas.workbench.hide()
	if simulation.phase == "event":
		hud.show_event(simulation.active_event)
		return
	_pending_start_draft.clear()
	var entering_revision := simulation.publish_count > 0 and simulation.phase != "draft"
	if entering_revision: simulation.begin_revision()
	atlas.set_speed(0)
	if entering_revision and not simulation.latest_draft.is_empty(): hud.set_draft(simulation.latest_draft)
	hud.show_workbench(true)
	_render()

func _on_event(event: Dictionary) -> void:
	atlas.set_speed(0)
	hud.show_event(event)

func _read_intelligence(instance_id: String) -> void:
	# Only a completed physical retraction may acknowledge this exact active event.
	if simulation.phase != "event" or str(simulation.active_event.get("instance_id", "")) != instance_id: return
	if tools.visible or hud.menu_mode() != "":
		_pending_read_id = instance_id
		return
	_pending_read_id = ""
	simulation.acknowledge_event()
	atlas.set_speed(0 if _interface_paused() or hud.get_node("%Workbench").visible else simulation.speed)

func _acknowledge() -> void:
	if desk != null and desk.get("_fax") != null: return
	if _interface_paused(): return
	if simulation.phase != "event":
		hud.dismiss_fax()
		atlas.set_speed(0 if hud.get_node("%Workbench").visible else simulation.speed)
		return
	simulation.acknowledge_event()
	atlas.set_speed(simulation.speed)

func _open_tools() -> void:
	_tool_speed = _menu_resume_speed if hud.menu_mode() != "" else simulation.speed
	simulation.set_speed(0)
	atlas.set_speed(0)
	hud.set_menu("")
	tools.show()
	desk._sync_reader_blocks()

func _close_tools() -> void:
	tools.hide()
	desk._sync_reader_blocks()
	_set_speed(_tool_speed, true)
	simulation.status = "事件开发副本已关闭；保存目录在下一次新局加载，不改变当前运行。"
	_render()

func _interface_paused() -> bool:
	return tools.visible or hud.menu_mode() != "" or desk.interaction_paused() or (_shell != null and _shell.blocks_input())

func _toggle_menu(mode: String) -> void:
	if hud.menu_mode() == mode and not tools.visible:
		_close_menu()
		return
	if hud.menu_mode() == "" and not tools.visible: _menu_resume_speed = simulation.speed
	if tools.visible:
		_menu_resume_speed = _tool_speed
		tools.hide()
	simulation.set_speed(0)
	atlas.set_speed(0)
	hud.set_menu(mode)
	desk._sync_reader_blocks()

func _close_menu() -> void:
	hud.set_menu("")
	desk._sync_reader_blocks()
	if _shell != null and _shell.main_mode:
		_shell.show_main()
		return
	if simulation.phase == "running": _set_speed(_menu_resume_speed, true)
	else: atlas.set_speed(0)

func _input(event: InputEvent) -> void:
	if not _ready_to_run or not event is InputEventKey or not event.pressed or event.echo: return
	var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_ESCAPE:
		if _shell != null and _shell.main_mode:
			if hud.menu_mode() != "": _close_menu()
			else: _shell.main_menu.close_settings()
		else: _toggle_menu("settings")
	elif key == KEY_D and event.ctrl_pressed:
		_toggle_menu("developer")
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit or _interface_paused() or simulation.phase == "event": return
		match key:
			KEY_SPACE: _set_speed(atlas.clock.previous_speed if simulation.speed == 0 else 0)
			KEY_COMMA, KEY_LESS: _set_speed(maxi(0, simulation.speed - 1))
			KEY_PERIOD, KEY_GREATER: _set_speed(mini(2, simulation.speed + 1))
			_: return
	get_viewport().set_input_as_handled()

func _save() -> void:
	var paused_speed := simulation.speed
	# A modal pause should not replace the saved running intent.
	if simulation.phase == "running" and (tools.visible or hud.menu_mode() != ""):
		simulation.speed = _tool_speed if tools.visible else _menu_resume_speed
	var error := store.save_run(simulation, SAVE_PATH)
	simulation.speed = paused_speed
	simulation.status = "已保存：" + SAVE_PATH if error == OK else "保存失败 %s：%s" % [error_string(error), "; ".join(store.last_errors)]
	_render()

func _load() -> bool:
	var error := store.load_run(simulation, SAVE_PATH)
	if error != OK:
		simulation.status = "读档被拒绝，当前局未改变：%s %s" % [error_string(error), "; ".join(store.last_errors)]
		_render()
		return false
	atlas.set_meta("demo_external_clock", simulation.gameplay_mode() == "world_competition")
	_pending_read_id = ""
	desk.reset_journal()
	_pending_start_draft.clear()
	if tools.visible or hud.menu_mode() != "":
		_menu_resume_speed = simulation.speed
		simulation.set_speed(0)
	atlas.clock.reset()
	atlas.close_drawer()
	atlas.setup_note.show()
	for index in atlas.settings.countries.size():
		if str(atlas.settings.countries[index].id) == simulation.country_id:
			atlas.select_country(index)
			atlas.establish_studio()
			break
	_clock_anchor = atlas.clock.utc_seconds
	atlas.clock.utc_seconds += simulation.hour * 3600.0
	atlas.set_speed(simulation.speed)
	atlas._update_clock()
	if not simulation.latest_draft.is_empty(): hud.set_draft(simulation.latest_draft)
	_startup_complete = simulation.publish_count > 0
	if simulation.publish_count == 0: _begin_startup()
	else: hud.show_workbench(simulation.phase == "draft")
	if simulation.phase == "event": hud.show_event(simulation.active_event)
	if simulation.phase == "complete": _complete_run(simulation.snapshot())
	_render()
	return true

func _restart() -> void:
	if not _load_catalog(): return
	_pending_read_id = ""
	get_node("DeskLayer/Desk").reset_journal()
	_pending_start_draft.clear()
	tools.hide()
	hud.set_menu("")
	_menu_resume_speed = 0
	simulation.catalog = catalog
	simulation.reset(simulation.seed_value + 1)
	if not _bind_world(): return
	if _shell != null: _shell.enter_game(false)
	hud.configure(catalog)
	tools.configure(catalog)
	atlas.clock.reset()
	atlas.close_drawer()
	atlas.setup_note.show()
	simulation.bind_country("", "未选择投放国家")
	_clock_anchor = atlas.clock.utc_seconds
	_begin_startup()
	_render()

func startup_ready() -> bool:
	return simulation != null and (simulation.publish_count > 0 or _startup_complete)

func open_startup_call() -> void:
	if not _ready_to_run or startup_ready() or tools.visible or hud.menu_mode() != "": return
	desk._fax.focus()

func _begin_startup() -> void:
	_startup_complete = false
	_pending_start_draft.clear()
	atlas.set_speed(0)
	hud.show_workbench(false)
	var chosen := str(simulation.snapshot().get("design_state", {}).get("starter_preset_id", ""))
	if not desk._fax.offer_starters(simulation.starter_options(), chosen):
		simulation.status = "起始模因来电未能建立，请检查内容目录。"
		return
	simulation.status = "67 来电：接听并选择一份起始模因。"
	_queue_startup_focus()

func _select_starter(preset_id: String) -> void:
	if not _ready_to_run or tools.visible or hud.menu_mode() != "" or startup_ready(): return
	var errors := simulation.design_action("choose_starter", {"preset_id":preset_id})
	if not errors.is_empty():
		desk._fax.reject_starter("；".join(errors))
		return
	var draft: Dictionary = simulation.context_draft()
	var draft_errors := simulation.validate_draft(draft)
	if not draft_errors.is_empty():
		desk._fax.reject_starter("；".join(draft_errors))
		return
	hud.set_draft(draft)
	desk._fax.confirm_starter(preset_id)
	_tutorial_observe("starter_chosen", {"id":preset_id})
	_render()

func _finish_startup(preset_id: String) -> void:
	if tools.visible or hud.menu_mode() != "" or simulation.publish_count > 0 or _startup_complete: return
	var chosen := str(simulation.snapshot().get("design_state", {}).get("starter_preset_id", ""))
	if chosen.is_empty() or chosen != preset_id: return
	var draft: Dictionary = hud.get_draft()
	if str(draft.get("preset_id", "")) != chosen or not simulation.validate_draft(draft).is_empty():
		hud.set_draft(simulation.context_draft())
	_startup_complete = true
	_tutorial_observe("startup_finished")
	desk._fax.close_focus()
	simulation.status = "起始模因已收到。先编辑、培养与配置传播，再确认投放国家。"
	hud.show_workbench(true)
	_render()

func _design_action(action: String, params: Dictionary) -> void:
	if not _ready_to_run or not startup_ready() or _interface_paused(): return
	var input := params.duplicate(true)
	var changes_draft := action in ["apply_context", "apply_skill", "install_module", "remove_module", "edit_module_content", "take_apply_context", "install_context", "remove_context", "move_context_axis", "detach_context_layer", "attach_context_layer"]
	if changes_draft: input["draft"] = hud.get_draft()
	var errors := simulation.design_action(action, input)
	if errors.is_empty() and changes_draft:
		var updated: Dictionary = simulation.context_draft()
		if not updated.is_empty(): hud.set_draft(updated)
	if errors.is_empty():
		if action == "install_module": _tutorial_observe("module_installed", params)
		if action == "install_context": _tutorial_observe("context_installed", params)
	hud.report_design_errors(errors)
	_render()

func _buy_skill(skill_id: String) -> void:
	if not _ready_to_run or not startup_ready() or _interface_paused(): return
	var errors := simulation.buy_propagation_skill(skill_id, hud.get_draft())
	if errors.is_empty():
		_tutorial_observe("skill_purchased", {"id":skill_id})
		var updated: Dictionary = simulation.context_draft()
		if not updated.is_empty(): hud.set_draft(updated)
	hud.report_design_errors(errors)
	_render()

func _request_event_material(record: Dictionary) -> PackedStringArray:
	if not _ready_to_run or not startup_ready() or tools.visible or hud.menu_mode() != "" or desk._stack.is_switching():
		return PackedStringArray(["先放下手里的工作，再取这份物资。"])
	var errors: PackedStringArray = simulation.request_event_material(str(record.get("instance_id", "")), str(record.get("kind", "")), str(record.get("id", "")))
	if not errors.is_empty(): hud.report_design_errors(errors)
	return errors

func _claim_design_reward(instance_id: String) -> void:
	if not _ready_to_run or not startup_ready() or _interface_paused(): return
	var errors := simulation.claim_design_reward(instance_id)
	hud.report_design_errors(errors)
	_render()

func _render() -> void:
	if simulation == null: return
	hud.render(simulation.snapshot())
	if _ready_to_run:
		_sync_setup()
		spread.update_simulation(simulation)
		hud.set_legend(spread.legend_rows())

func inspection_state() -> Dictionary:
	return {"setup_stage":_setup_stage(), "startup_ready":startup_ready(), "simulation":simulation.snapshot(), "hud":hud.inspection(), "spread":spread.inspection(), "catalog_path":catalog.resource_path, "map_seed":_map_seed, "tools_visible":tools.visible, "clock":atlas.clock.inspection(), "shell":_shell.inspection() if _shell != null else {}}


func _bind_world() -> bool:
	atlas.set_meta("demo_external_clock", simulation.gameplay_mode() == "world_competition")
	var errors := simulation.bind_world(atlas.world,atlas.settings)
	if errors.is_empty(): return true
	_catalog_error("Cannot bind world: " + "; ".join(errors))
	return false

func _tutorial_observe(action: String, data: Dictionary = {}) -> void:
	if _shell != null: _shell.observe(action,data)

func _start_from_main() -> void:
	_restart()
	_shell.enter_game(true)
	_queue_startup_focus()

func _load_from_main() -> void:
	if _load():
		_shell.enter_game(false)
		if simulation.phase == "complete": _complete_run(simulation.snapshot())

func _open_main_codex() -> void:
	_shell.main_menu.hide_menu()
	_toggle_menu("codex")

func _return_to_main() -> void:
	atlas.set_speed(0)
	tools.hide()
	hud.set_menu("")
	hud.get_node("%ResultCard").hide()
	desk._fax.close_focus()
	_shell.show_main()
	_render()

func _complete_run(state: Dictionary) -> void:
	atlas.set_speed(0)
	if _shell != null and _shell.ending.show_result(state):
		_shell.main_menu.hide_menu()
		_shell.tutorial.skip()
	else:
		hud.show_result(state)


func _queue_startup_focus() -> void:
	if _shell == null or _shell.main_mode: return
	if desk._stack.is_switching():
		if not desk._stack.switch_completed.is_connected(_focus_startup_call):
			desk._stack.switch_completed.connect(_focus_startup_call,CONNECT_ONE_SHOT)
	else: _focus_startup_call()

func _focus_startup_call(_sheet: String = "") -> void:
	if _shell == null or _shell.main_mode or startup_ready(): return
	desk._sync_reader_blocks()
	desk._fax.focus()
