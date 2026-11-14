extends Node2D

signal initialization_finished(error: Error)
signal initialization_progress(stage: String)
var initialization_complete := false
var initialization_error: Error = ERR_UNCONFIGURED
var initialization_message := ""

const SAVE_PATH := "user://saves/current_run.json"
const KeyBindings := preload("res://scripts/presentation/ui/menus/key_bindings.gd")

@onready var atlas: Node2D = $Atlas
@onready var hud: Control = $DemoLayer/HUD
@onready var spread: Control = $SpreadLayer/SpreadOverlay
@onready var desk: Control = $DeskLayer/Desk

var catalog: MemeDemoCatalog
var simulation: MemeDemoSimulation
var store := MemeDemoStore.new()
var _clock_anchor: float = 0.0
var _map_seed: int = 0
var _menu_resume_speed: int = 0
var _ready_to_run := false
var _pending_read_id: String = ""
var _startup_complete: bool = false
var _direct_starter_selection := false
var _direct_starter_index := -1
var _shell: CanvasLayer
var _tutorial_country := -1
var _context_trial_queued := false
var _context_trial_signature := ""
var _context_trial_seed := -1
var _context_trial_skills: Array = []

func _ready() -> void:
	set_process(false)
	atlas.initial_seed = store.startup_world_seed(SAVE_PATH)
	var localization_error := DeskLocalization.ensure_loaded()
	if localization_error != OK:
		_fail_initialization("Cannot load interface translations", localization_error)
		return
	atlas.process_priority = 20
	await _initialization_stage("LOC_LOADING_WORLD")
	if not atlas.initialization_complete:
		await atlas.initialization_finished
	if atlas.initialization_error != OK:
		_fail_initialization(atlas.initialization_message, atlas.initialization_error)
		return
	_map_seed = atlas.world.seed_value
	_clock_anchor = atlas.clock.utc_seconds
	await _initialization_stage("LOC_LOADING_CONFIGURATION")
	if not _load_catalog(): return
	simulation = MemeDemoSimulation.new(catalog, atlas.world)
	simulation.changed.connect(_render)
	simulation.event_raised.connect(_on_event)
	simulation.completed.connect(_complete_run)
	await _initialization_stage("LOC_LOADING_INTERFACE")
	hud.configure(catalog)
	hud.draft_publish_requested.connect(_publish)
	hud.country_selection_requested.connect(_choose_country)
	hud.speed_requested.connect(_set_speed)
	hud.step_requested.connect(_step)
	hud.workbench_requested.connect(_open_workbench)
	hud.save_requested.connect(_save)
	hud.load_requested.connect(_load)
	hud.restart_requested.connect(_restart)
	hud.event_acknowledged.connect(_acknowledge)
	hud.settings_requested.connect(_open_settings)
	hud.developer_requested.connect(func(): _toggle_menu("developer"))
	hud.quit_requested.connect(func(): get_tree().quit())
	hud.menu_close_requested.connect(_close_menu)
	hud.design_action_requested.connect(_design_action)
	hud.skill_purchase_requested.connect(_buy_skill)
	atlas.set_process_input(false)
	atlas.launch_confirmed.connect(_studio_selected)
	atlas.get_node("%SpeedControl").pressed.connect(func(): _set_speed(atlas.clock.speed))
	await _initialization_stage("LOC_LOADING_DESK")
	desk.configure(self)
	spread.configure(atlas)
	atlas.configure_meme_tracking(spread, catalog)
	hud.layout_for_date(desk.clock_rect())
	desk._fax.starter_selected.connect(_select_starter)
	desk._fax.startup_finished.connect(_finish_startup)
	desk._camera.overview_arrived.connect(func():
		if _direct_starter_selection and _shell != null and not _shell.main_mode: _show_direct_starters())
	if not _bind_world(): return
	_shell = preload("res://scripts/presentation/ui/menus/game_shell.gd").new()
	_shell.name = "GameShell"
	add_child(_shell)
	_shell.configure(self)
	_ready_to_run = true
	_refresh_locale.call_deferred()
	desk._fax.starter_previewed.connect(func(id: String): _tutorial_observe("starter_previewed", {"id":id}))
	desk._fax.call_changed.connect(func(record: Dictionary):
		if str(record.get("kind", "")) == "connected": _tutorial_observe("phone_pickup"))
	_render()
	set_process(true)
	initialization_error = OK
	initialization_complete = true
	initialization_finished.emit(OK)
	print("MEME_DEMO_READY content=%d events=%d groups=%d kernels=%d" % [catalog.content_version, catalog.events.size(), catalog.groups.size(), catalog.kernels.size()])

func _initialization_stage(stage: String) -> void:
	initialization_progress.emit(stage)
	await RenderingServer.frame_post_draw

func _load_catalog() -> bool:
	var path := "res://data/catalogs/catalog.tres"
	var candidate := load(path) as MemeDemoCatalog
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
	_fail_initialization(message, ERR_INVALID_DATA)
	if simulation != null:
		simulation.status = message
		_render()
	else:
		hud.get_node("%Status").text = message

func _process(delta: float) -> void:
	if not _ready_to_run: return
	if not _pending_read_id.is_empty() and hud.menu_mode().is_empty():
		_read_intelligence(_pending_read_id)
	if atlas.world.seed_value != _map_seed:
		_map_seed = atlas.world.seed_value
		simulation.reset(simulation.seed_value + 1, atlas.world)
		if not _bind_world(): return
		simulation.bind_country("", DeskLocalization.source("LOC_NO_DEPLOYMENT_COUNTRY_SELECTED_989E9AAC"))
		_clock_anchor = atlas.clock.utc_seconds
		_begin_startup()
	_sync_setup()
	if _setup_stage() == "country" and atlas.selected_country >= 0 and atlas.selected_country != _tutorial_country:
		_tutorial_country = atlas.selected_country
		_tutorial_observe("country_selected", {"index":atlas.selected_country})
	if _shell != null:
		_shell.tutorial.set_interaction_blocked(hud.modal_visible())
		_shell.starter_dialog.set_interaction_blocked(hud.modal_visible())
	if simulation.phase != "running" or _clock_paused():
		atlas.set_speed(0)
	else:
		simulation.advance_active_seconds(delta)
		atlas.clock.utc_seconds = _clock_anchor + simulation.elapsed_hours() * 3600.0
		atlas._update_clock()
		atlas.set_speed(clock_speed())
	hud.layout_for_date(desk.clock_rect())
	_queue_context_trial()

func _studio_selected() -> void:
	if not _ready_to_run: return
	if not startup_ready() or _interface_paused() or simulation.publish_count != 0:
		atlas.reset_launch_confirmation()
		return
	if _shell.tutorial._active and str(_shell.tutorial.inspection().step.get("action", "")) != "published":
		atlas.reset_launch_confirmation()
		return
	var index: int = atlas.selected_country
	if index < 0 or index >= atlas.settings.countries.size():
		simulation.status = DeskLocalization.source("LOC_SELECT_A_DEPLOYMENT_COUNTRY_ON_THE_MAP_18ADCDE2")
		atlas.reset_launch_confirmation()
		_render()
		return
	# The bubble commits the current editor state, never an earlier confirmation copy.
	var draft: Dictionary = hud.get_draft()
	var errors := _draft_errors(draft)
	if not errors.is_empty():
		simulation.status = DeskLocalization.source_join("；",errors)
		atlas.reset_launch_confirmation()
		_render()
		return
	if not _commit_draft(draft, index): atlas.reset_launch_confirmation()
	_render()

func _bind_country(index: int) -> void:
	var country: Resource = atlas.settings.countries[index]
	simulation.bind_country(str(country.id), tr(country.short_name_key))

func _publish(draft: Dictionary) -> void:
	if not _ready_to_run or _interface_paused(): return
	if not startup_ready():
		simulation.status = DeskLocalization.source("LOC_ANSWER_S_CALL_SELECT_A_STARTING_MEME_9CFFACED")
		_render()
		return
	if simulation.publish_count == 0:
		_choose_country()
		return
	# Turning a page is presentation only; a new version starts at explicit publish.
	var revision_view: bool = simulation.publish_count > 0 and simulation.phase in ["running", "complete"] and hud.get_node("%Workbench").visible
	var errors := _draft_errors(draft, revision_view)
	if not errors.is_empty():
		simulation.status = DeskLocalization.source_join("；",errors)
		_render()
		return
	if revision_view:
		var revision_errors := simulation.begin_revision(draft)
		if not revision_errors.is_empty():
			hud.report_design_errors(revision_errors)
			return
		draft = simulation.latest_draft.duplicate(true)
		hud.set_draft(draft)
	var index: int = atlas.selected_country if atlas.selected_country >= 0 else atlas.clock.studio_index
	_commit_draft(draft, index)

func _draft_errors(draft: Dictionary, revision_view: bool = false) -> PackedStringArray:
	var errors := simulation.validate_draft(draft)
	if simulation.phase != "draft" and not revision_view: errors.append(DeskLocalization.source("LOC_RETURN_TO_THE_WORKBENCH_AND_CREATE_YOUR_1A4056D3"))
	var cost: int = catalog.first_publish_cost if simulation.publish_count == 0 else catalog.revision_publish_cost
	if simulation.economy.balance < cost:
		errors.append(DeskLocalization.format_text("LOC_NOT_ENOUGH_MEME_NEED_D_HAVE_D_46321C6B", [cost, simulation.economy.balance]))
	return errors

func _commit_draft(draft: Dictionary, index: int) -> bool:
	if index < 0 or index >= atlas.settings.countries.size():
		simulation.status = DeskLocalization.source("LOC_SELECT_A_DEPLOYMENT_COUNTRY_ON_THE_MAP_AA28A76D")
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
		atlas.clock.utc_seconds += simulation.elapsed_hours() * 3600.0
		atlas._update_clock()
	_clock_anchor = atlas.clock.utc_seconds - simulation.elapsed_hours() * 3600.0
	hud.show_workbench(false)
	atlas.close_drawer()
	atlas.set_speed(simulation.speed)
	_tutorial_observe("published")
	_render()
	return true

func _choose_country() -> void:
	if not _ready_to_run or _interface_paused(): return
	desk.select_sheet("map")

func _setup_stage() -> String:
	if not startup_ready(): return "starter_call"
	if simulation.publish_count == 0: return "country"
	if simulation.phase == "draft": return "revision"
	return "playing" if simulation.phase == "running" else simulation.phase

func _sync_setup() -> void:
	var stage := _setup_stage()
	hud.set_setup_stage(stage)
	atlas.map_input.mouse_filter = Control.MOUSE_FILTER_IGNORE if stage == "starter_call" or _interface_paused() or hud.get_node("%Workbench").visible else Control.MOUSE_FILTER_STOP
	atlas.set_launch_selection_active(stage == "country" and not _interface_paused() and not hud.get_node("%Workbench").visible)

func _set_speed(value: int, restore_intent: bool = false) -> void:
	if _clock_paused():
		if restore_intent and simulation.phase == "running": simulation.set_speed(value)
		atlas.set_speed(0)
		return
	simulation.set_speed(value)
	atlas.set_speed(clock_speed())
	if simulation.phase == "running" and simulation.speed == value: _tutorial_observe("speed_changed", {"speed":value})

func _step() -> void:
	if _clock_paused(): return
	simulation.set_speed(0)
	atlas.set_speed(0)
	if simulation.step_hour():
		atlas.clock.utc_seconds = _clock_anchor + simulation.elapsed_hours() * 3600.0
		atlas._update_clock()

func _open_workbench() -> void:
	if not _ready_to_run or _interface_paused(): return
	if not startup_ready():
		desk._fax.focus()
		return
	if simulation.phase == "event":
		hud.show_event(simulation.active_event)
		return
	# Browsing the workbench does not start a revision; explicit publication does.
	hud.show_workbench(true)
	_render()

func _on_event(event: Dictionary) -> void:
	hud.show_event(event)
	# Ordinary intelligence is committed on receipt; its physical printing is asynchronous.
	if event.get("design_rewards", []).is_empty():
		simulation.status = DeskLocalization.source_format("LOC_RECEIVED_D_MESSAGES_B3820ECB", simulation.events.size())
		simulation.acknowledge_event()
	else:
		simulation.status = DeskLocalization.source("LOC_THIS_FAX_INCLUDES_MATERIALS_MOVE_THE_CARD_4D9E87DA")
	atlas.set_speed(clock_speed())

func _event_has_pending_material(instance_id: String) -> bool:
	for record: Dictionary in simulation.event_materials():
		if str(record.instance_id) == instance_id and not bool(record.requested): return true
	return false

func _read_intelligence(instance_id: String) -> void:
	# Printing alone cannot release a material event; its physical card must be taken.
	if simulation.phase != "event" or str(simulation.active_event.get("instance_id", "")) != instance_id: return
	if _event_has_pending_material(instance_id): return
	if hud.menu_mode() != "":
		_pending_read_id = instance_id
		return
	_pending_read_id = ""
	simulation.status = DeskLocalization.source_format("LOC_RECEIVED_D_MESSAGES_B3820ECB", simulation.events.size())
	simulation.acknowledge_event()
	atlas.set_speed(clock_speed())

func _acknowledge() -> void:
	if desk != null and desk.get("_fax") != null: return
	if _interface_paused(): return
	if simulation.phase != "event":
		hud.dismiss_fax()
		atlas.set_speed(clock_speed())
		return
	simulation.acknowledge_event()
	atlas.set_speed(simulation.speed)

func _interface_paused() -> bool:
	return hud.menu_mode() != "" or desk.interaction_paused() or (_shell != null and _shell.blocks_input())

func _clock_paused() -> bool:
	return hud.modal_visible() or (_shell != null and _shell.pauses_clock()) or desk._fax.has_pending_materials()

func clock_speed() -> int:
	return simulation.speed if simulation.phase == "running" and not _clock_paused() else 0

func _toggle_menu(mode: String) -> void:
	if hud.menu_mode() == mode:
		_close_menu()
		return
	if hud.menu_mode().is_empty(): _menu_resume_speed = simulation.speed
	simulation.set_speed(0)
	atlas.set_speed(0)
	hud.set_menu(mode)
	desk._sync_reader_blocks()

func _close_menu() -> void:
	hud.set_menu("")
	if _direct_starter_selection: _show_direct_starters()
	desk._sync_reader_blocks()
	if _shell != null and _shell.main_mode:
		_shell.show_main()
		return
	if simulation.phase == "running": _set_speed(_menu_resume_speed, true)
	else: atlas.set_speed(0)

func _open_settings() -> void:
	hud.set_menu("preferences")
	_shell.main_menu.show_settings()
	desk._sync_reader_blocks()

func _input(event: InputEvent) -> void:
	if not _ready_to_run or not event is InputEventKey or not event.pressed or event.echo: return
	var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_ESCAPE:
		if _shell != null and _shell.main_menu.visible:
			_shell.main_menu.back()
			get_viewport().set_input_as_handled()
			return
		if _shell != null and _shell.is_choosing_starter():
			_toggle_menu("settings")
			get_viewport().set_input_as_handled()
			return
		if hud.menu_mode() == "" and desk != null and desk.slot_details_active():
			desk.close_slot_details()
			get_viewport().set_input_as_handled()
			return
		if hud.menu_mode() == "" and desk != null and desk._camera != null and desk._camera.inspection().state != "overview":
			_return_to_desktop()
			get_viewport().set_input_as_handled()
			return
		if _shell != null and _shell.main_mode:
			if hud.menu_mode() != "": _close_menu()
			else: _shell.main_menu.close_settings()
		else: _toggle_menu("settings")
	elif key == KEY_D and event.ctrl_pressed:
		_toggle_menu("developer")
	else:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit or _clock_paused() or simulation.phase == "event": return
		if KeyBindings.matches(event, "pause"): _set_speed(atlas.clock.previous_speed if simulation.speed == 0 else 0)
		elif KeyBindings.matches(event, "slower"): _set_speed(maxi(0, simulation.speed - 1))
		elif KeyBindings.matches(event, "faster"): _set_speed(mini(2, simulation.speed + 1))
		elif KeyBindings.matches(event, "speed_paused"): _set_speed(0)
		elif KeyBindings.matches(event, "speed_normal"): _set_speed(1)
		elif KeyBindings.matches(event, "speed_fast"): _set_speed(2)
		else: return
	get_viewport().set_input_as_handled()

func _save() -> void:
	var paused_speed := simulation.speed
	# A modal pause should not replace the saved running intent.
	if simulation.phase == "running" and (hud.menu_mode() != ""):
		simulation.speed = _menu_resume_speed
	var error := store.save_run(simulation, SAVE_PATH)
	simulation.speed = paused_speed
	simulation.status = DeskLocalization.source_format("LOC_SAVED_S_C5E73322",SAVE_PATH) if error == OK else DeskLocalization.source_format("LOC_SAVE_FAILED_S_S_81E5BCAD", [error_string(error), "; ".join(store.last_errors)])
	_render()

func _load() -> bool:
	var error := store.load_run(simulation, SAVE_PATH)
	if error != OK:
		simulation.status = DeskLocalization.source_format("LOC_LOAD_REJECTED_THE_CURRENT_RUN_IS_UNCHANGED_58D375FE", [error_string(error), DeskLocalization.source_join("; ", store.last_errors)], [1])
		_render()
		return false
	atlas.set_meta("demo_external_clock", true)
	_pending_read_id = ""
	if _shell != null: _shell.context_guidance.close()
	desk.reset_journal()
	if hud.menu_mode() != "":
		_menu_resume_speed = simulation.resume_speed if simulation.phase == "event" else simulation.speed
		simulation.set_speed(0)
	atlas.clock.reset()
	atlas.close_drawer()
	for index in atlas.settings.countries.size():
		if str(atlas.settings.countries[index].id) == simulation.country_id:
			atlas.select_country(index)
			atlas.establish_studio()
			break
	_clock_anchor = atlas.clock.utc_seconds
	atlas.clock.utc_seconds += simulation.elapsed_hours() * 3600.0
	atlas.set_speed(simulation.speed)
	atlas._update_clock()
	if not simulation.context_draft().is_empty(): hud.set_draft(simulation.context_draft())
	_startup_complete = simulation.publish_count > 0
	_direct_starter_selection = false
	_direct_starter_index = -1
	if simulation.publish_count == 0: _begin_startup()
	else: hud.show_workbench(simulation.phase == "draft")
	if simulation.phase == "event": _on_event(simulation.active_event.duplicate(true))
	if simulation.phase == "complete": _complete_run(simulation.snapshot())
	_render()
	return true

func _restart() -> void:
	await _shell.loading.present("LOC_LOADING_STARTING")
	if _shell != null: _shell.context_guidance.close()
	if not _load_catalog():
		_shell.loading.fail()
		return
	_pending_read_id = ""
	get_node("DeskLayer/Desk").reset_journal()
	hud.set_menu("")
	_menu_resume_speed = 0
	simulation.catalog = catalog
	simulation.reset(simulation.seed_value + 1, atlas.world)
	if not _bind_world():
		_shell.loading.fail()
		return
	hud.configure(catalog)
	atlas.clock.reset()
	atlas.close_drawer()
	simulation.bind_country("", DeskLocalization.source("LOC_NO_DEPLOYMENT_COUNTRY_SELECTED_989E9AAC"))
	_clock_anchor = atlas.clock.utc_seconds
	_begin_startup()
	_render()
	desk.return_overview()
	desk._monitor.set_mode("meme")
	if _shell != null: _shell.enter_game(true)
	_shell.loading.finish()
	_queue_startup_focus()

func startup_ready() -> bool:
	return simulation != null and (simulation.publish_count > 0 or _startup_complete)

func open_startup_call() -> void:
	if not _ready_to_run or startup_ready() or hud.menu_mode() != "": return
	if _direct_starter_selection:
		_show_direct_starters()
		return
	desk._fax.focus()

func _begin_startup() -> void:
	_startup_complete = false
	_direct_starter_selection = _shell != null and not _shell.main_menu.guide_enabled()
	_direct_starter_index = -1
	_tutorial_country = -1
	atlas.set_speed(0)
	hud.show_workbench(false)
	if _direct_starter_selection:
		desk._fax.clear_starter_offer()
		simulation.status = DeskLocalization.source("LOC_GUIDANCE_CHOOSE_STARTER")
		if _shell != null and not _shell.main_mode: _show_direct_starters()
		return
	var chosen := str(simulation.snapshot().get("design_state", {}).get("starter_preset_id", ""))
	if not desk._fax.offer_starters(simulation.starter_options(), chosen):
		simulation.status = DeskLocalization.source("LOC_COULD_NOT_ESTABLISH_THE_STARTING_MEME_CALL_BBAAE077")
		return
	simulation.status = DeskLocalization.source("LOC_IS_CALLING_ANSWER_AND_CHOOSE_A_STARTING_3E32F621")

func _select_starter(preset_id: String) -> void:
	if not _ready_to_run or hud.menu_mode() != "" or startup_ready(): return
	var errors := simulation.design_action("choose_starter", {"preset_id":preset_id})
	if not errors.is_empty():
		desk._fax.reject_starter(DeskLocalization.source_join("；",errors))
		return
	var draft: Dictionary = simulation.context_draft()
	var draft_errors := simulation.validate_draft(draft)
	if not draft_errors.is_empty():
		desk._fax.reject_starter(DeskLocalization.source_join("；",draft_errors))
		return
	hud.set_draft(draft)
	hud.design_workbench().mark_catalog_defaults(preset_id)
	if not _direct_starter_selection: desk._fax.confirm_starter(preset_id)
	_tutorial_observe("starter_chosen", {"id":preset_id})
	_render()
	if _direct_starter_selection:
		_finish_startup(preset_id)
		_direct_starter_selection = false
		desk._slot_reader.hide_details()
		desk.return_overview()

func _show_direct_starters() -> void:
	if startup_ready(): return
	_direct_starter_selection = true
	if _shell != null: _shell.tutorial.skip()
	var chosen := str(simulation.design_state.snapshot().get("starter_preset_id", ""))
	if not chosen.is_empty():
		_finish_startup(chosen)
		if startup_ready():
			if str(desk._fax.inspection().call_state) == "connected":
				desk._fax._call_session.hangup(true, true)
				desk._fax._refresh_call_view()
			_direct_starter_selection = false
			desk._slot_reader.hide_details()
			_shell.starter_dialog.skip()
			_shell.starter_dialog.hide()
			desk.return_overview()
		return
	desk._fax.reset_station()
	var options: Array[Dictionary] = []
	var starters: Array = simulation.starter_options()
	for index in starters.size():
		var option: Dictionary = starters[index]
		options.append({"id":option.id, "title":option.title, "description":option.context_hint, "context_hint":option.context_hint, "default_context":option.default_context, "action":"starter_preview", "index":index, "selected":index == _direct_starter_index, "disabled":false})
	desk._slot_reader.hide_details()
	_shell.show_direct_starters(options, _direct_starter_index)

func _direct_starter_choice(index: int) -> void:
	if not _direct_starter_selection or startup_ready() or hud.menu_mode() != "" or (_shell != null and _shell.blocks_input()): return
	var options: Array = simulation.starter_options()
	if index >= 0 and index < options.size():
		_direct_starter_index = index
		_show_direct_starters()
	elif index == options.size() and _direct_starter_index >= 0:
		_select_starter(str(options[_direct_starter_index].id))

func _finish_startup(preset_id: String) -> void:
	if hud.menu_mode() != "" or simulation.publish_count > 0 or _startup_complete: return
	var chosen := str(simulation.snapshot().get("design_state", {}).get("starter_preset_id", ""))
	if chosen.is_empty() or chosen != preset_id: return
	var draft: Dictionary = hud.get_draft()
	if str(draft.get("preset_id", "")) != chosen or not simulation.validate_draft(draft).is_empty():
		hud.set_draft(simulation.context_draft())
	_startup_complete = true
	_tutorial_observe("startup_finished")
	desk._fax.close_focus()
	simulation.status = DeskLocalization.source("LOC_STARTING_MEME_RECEIVED_EDIT_CULTIVATE_AND_CONFIGURE_AE28DEF3")
	hud.show_workbench(false)
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
		if action == "remove_context": _tutorial_observe("context_removed", params)
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
	if not _ready_to_run or not startup_ready() or hud.menu_mode() != "" or desk._stack.is_switching():
		return PackedStringArray([DeskLocalization.source("LOC_PUT_DOWN_WHAT_YOU_ARE_HOLDING_BEFORE_B69F635E")])
	var errors: PackedStringArray = simulation.request_event_material(str(record.get("instance_id", "")), str(record.get("kind", "")), str(record.get("id", "")))
	if not errors.is_empty(): hud.report_design_errors(errors)
	elif desk._fax.event_delivered(str(record.get("instance_id", ""))):
		_read_intelligence(str(record.instance_id))
	return errors

func _render() -> void:
	if simulation == null: return
	var snapshot := simulation.snapshot()
	hud.render(snapshot)
	_context_trial_skills = Array(snapshot.get("design_state", {}).get("unlocked_skills", []))
	if _ready_to_run:
		_sync_setup()
		spread.update_simulation(simulation)
		atlas.update_meme_state(snapshot)
		if _shell != null: _shell.context_guidance.observe_world(snapshot.world_competition)
		hud.set_legend(spread.legend_rows())
		_queue_context_trial()

func focus_meme_on_map(id: String) -> void:
	if desk.focus_component("sheet/map"):
		hud.show_sheet("map")
		atlas.select_meme(id)

func _queue_context_trial() -> void:
	if _context_trial_queued or not _ready_to_run or desk.get("_active_sheet") != "cultivate": return
	_context_trial_queued = true
	_update_context_trial.call_deferred()

func _update_context_trial() -> void:
	_context_trial_queued = false
	if not _ready_to_run or desk.get("_active_sheet") != "cultivate": return
	var editor: Control = hud.design_workbench()
	if _context_trial_seed != simulation.seed_value:
		_context_trial_seed = simulation.seed_value
		_context_trial_signature = ""
		editor.reset_context_trial()
	var country_id := simulation.country_id
	var country_title := simulation.country_title
	if atlas.selected_country >= 0 and atlas.selected_country < atlas.settings.countries.size():
		var country: Resource = atlas.settings.countries[atlas.selected_country]
		country_id = str(country.id)
		country_title = tr(country.short_name_key)
	var draft: Dictionary = hud.get_draft()
	var signature := JSON.stringify([country_id, country_title, draft, _context_trial_skills])
	if signature == _context_trial_signature: return
	_context_trial_signature = signature
	# A drag may request several steps; compare only its settled draft once per frame.
	var report: Dictionary = {} if country_id.is_empty() else simulation.draft_fitness(draft).get("countries", {}).get(country_id, {})
	editor.set_context_trial(country_id, country_title, report)

func inspection_state() -> Dictionary:
	return {"setup_stage":_setup_stage(), "startup_ready":startup_ready(), "simulation":simulation.snapshot(), "hud":hud.inspection(), "spread":spread.inspection(), "catalog_path":catalog.resource_path, "map_seed":_map_seed, "clock":atlas.clock.inspection(), "shell":_shell.inspection() if _shell != null else {}}


func _bind_world() -> bool:
	atlas.set_meta("demo_external_clock", true)
	var errors := simulation.bind_world(atlas.world,atlas.settings)
	if errors.is_empty(): return true
	_catalog_error("Cannot bind world: " + "; ".join(errors))
	return false

func _tutorial_observe(action: String, data: Dictionary = {}) -> void:
	if _shell != null: _shell.observe(action,data)

func _start_from_main() -> void:
	await _restart()

func _load_from_main() -> void:
	await _shell.loading.present("LOC_LOADING_SAVE")
	if _load():
		_shell.enter_game(false)
		if simulation.phase == "complete": _complete_run(simulation.snapshot())
	else:
		_shell.main_menu.report_load_error(simulation.status)
	_shell.loading.finish()

func _return_to_main() -> void:
	atlas.set_speed(0)
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
		_shell.context_guidance.close()
	else:
		hud.show_result(state)


func _return_to_desktop() -> void:
	var call: Dictionary = desk._fax.inspection()
	if not startup_ready() and str(call.call_state) == "connected" and not str(call.starter_id).is_empty():
		desk._fax.hangup()
	desk.return_overview()

func _queue_startup_focus() -> void:
	if _shell == null or _shell.main_mode: return
	if desk._stack.is_switching():
		if not desk._stack.switch_completed.is_connected(_focus_startup_call):
			desk._stack.switch_completed.connect(_focus_startup_call,CONNECT_ONE_SHOT)
	else: _focus_startup_call()

func _focus_startup_call(_sheet: String = "") -> void:
	if _shell == null or _shell.main_mode or startup_ready(): return
	desk.focus_component("fax")

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and _ready_to_run:
		_refresh_locale.call_deferred()

func _refresh_locale() -> void:
	if not _ready_to_run or simulation == null: return
	DeskLocalization.refresh_edits(self)
	atlas.refresh_localization()
	hud.refresh_localization()
	_render()
	desk._clock_presenter.tick()

func _fail_initialization(message: String, error: Error) -> void:
	_ready_to_run = false
	set_process(false)
	initialization_error = error
	initialization_message = message
	push_error(message)
	if not initialization_complete:
		initialization_complete = true
		initialization_finished.emit(error)

func create_studio_adapter() -> RefCounted:
	return preload("res://scripts/presentation/studio/desk/studio_adapter.gd").new(desk)

func mount_presentation_overlays(parent: Node) -> void:
	_shell.reparent(parent)
	get_node("DeskCameraControls").reparent(parent)

func presentation_blocks_input() -> bool:
	return _shell.blocks_input()

func presentation_modal_visible() -> bool:
	return hud.modal_visible() and hud.menu_mode() != "preferences"

func presentation_daylight() -> float:
	return atlas.clock.daylight_fraction()
