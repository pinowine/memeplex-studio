extends Node

const Tutorial = preload("res://scripts/presentation/ui/tutorial/tutorial.gd")
const LESSONS := {"deviation":"LOC_GUIDANCE_DEVIATION", "competition":"LOC_GUIDANCE_FIRST_COMPETITOR", "mutation":"LOC_GUIDANCE_FIRST_MUTATION"}
const EMOTIONS := {"deviation":"concerned", "competition":"concerned", "mutation":"curious"}
var page: Node
var shell: Node
var mentor: Control
var enabled := true
var _lesson_id := ""
var _source_id := ""
var _mutation_queue: Array[String] = []
var _seen_mutations: Dictionary = {}
var _world_seed := -1

func configure(owner_shell: Node) -> void:
	shell = owner_shell
	page = shell.page
	mentor = Tutorial.new()
	mentor.name = "ContextMentor67"
	shell.add_child(mentor)
	mentor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mentor.set_input_target_provider(shell._tutorial_input_targets, shell._tutorial_input_contains)
	mentor.step_changed.connect(func(id: String, _step: Dictionary):
		if id == "mutation":
			var editor: Control = page.hud.design_workbench()
			editor._detail_scroll.ensure_control_visible.call_deferred(editor._final_expression))

func set_enabled(value: bool) -> void:
	enabled = value

func close() -> void:
	if mentor == null: return
	mentor.skip()
	mentor.hide()

func _record(id: String, source_id: String) -> void:
	page.simulation.queue_guidance(id, source_id)

func observe_world(world: Dictionary) -> void:
	if page == null or page.simulation == null: return
	if _world_seed != int(world.world_seed):
		_world_seed = int(world.world_seed)
		_seen_mutations.clear()
		_mutation_queue.clear()
	for variant: Dictionary in world.get("variants", []):
		var raw: Dictionary = page.simulation.variant_by_id(str(variant.id))
		var current: Dictionary = page.simulation.Lifecycle.content(raw)
		if bool(current.get("controlled", false)) and page.simulation.Deviation.total(raw.deviation_anchor, current) > .1:
			_record("deviation", str(raw.id))
		if str(raw.creator) != "player" and raw.get("origin_ids", []).is_empty() and not page.simulation.guidance_progress().has("competition"):
			_record("competition", str(raw.id))
		if str(raw.creator) != "player" and not raw.get("parent_ids", []).is_empty() and not raw.get("origin_ids", []).is_empty() and not _seen_mutations.has(str(variant.id)):
			_seen_mutations[str(variant.id)] = true
			_mutation_queue.append(str(variant.id))
			_record("mutation", str(variant.id))

func _process(_delta: float) -> void:
	if mentor == null or not page._ready_to_run: return
	var progress: Dictionary = page.simulation.guidance_progress()
	var blocked: bool = shell.main_mode or shell.main_menu.visible or shell.ending.visible or page.hud.modal_visible() or shell.tutorial._active or not page.startup_ready()
	if mentor._active:
		mentor.set_interaction_blocked(blocked)
		mentor.visible = not blocked
		mentor.set_process_input(mentor.visible)
		return
	if blocked: return
	progress = page.simulation.guidance_progress()
	for id: String in ["deviation", "mutation", "competition"]:
		if id == "mutation":
			if _mutation_queue.is_empty(): continue
		elif not progress.has(id) or bool(progress[id].shown): continue
		_lesson_id = id
		_source_id = _mutation_queue[0] if id == "mutation" else str(progress[id].source_id)
		if id == "mutation": page.hud.design_workbench()._select_variant(_source_id)
		var steps: Array[Dictionary] = [{"id":id, "text":LESSONS[id], "emotion":EMOTIONS[id], "action":"continue", "target":id, "contextual":true, "no_blur":true, "map_navigation":id == "competition"}]
		if id in ["mutation", "competition"]:
			if not str(page.desk._camera.inspection().target).begins_with("sheet/"): page.desk.return_overview()
			var sheet := "edit" if id == "mutation" else "map"
			if page.desk._active_sheet != sheet:
				steps.push_front({"id":id+"_navigate", "text":"LOC_GUIDANCE_"+id.to_upper()+"_NAVIGATE", "emotion":EMOTIONS[id], "action":"sheet_selected", "match":{"id":sheet}, "target":"sheet/"+sheet, "contextual":true, "no_blur":true})
		if id == "mutation":
			steps[-1].target = "editor/expression"
			steps[-1].scroll = true
			var raw: Dictionary = page.simulation.variant_by_id(_source_id)
			var change_text: String = page.hud.design_workbench().community_change_text(raw)
			var key := "LOC_GUIDANCE_MUTATION_SPLIT" if not bool(raw.get("effective_content", raw).get("owned", raw.owned)) else "LOC_GUIDANCE_MUTATION_EFFECT"
			steps[-1].text = DeskLocalization.format_text(key, change_text)
			_mutation_queue.pop_front()
		if id == "deviation":
			page.desk._monitor.set_mode("meme")
			steps[-1].target = "monitor/curve"
		mentor.configure(steps, _target, _reserved_areas)
		mentor.set_interaction_blocked(false)
		mentor.set_process_input(true)
		mentor.begin()
		page.simulation.mark_guidance_shown(id)
		break

func _project(control: Control) -> Rect2:
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return Rect2()
	return shell._tutorial_project_rect(control).intersection(mentor.get_viewport().get_visible_rect())

func _target(id: String) -> Rect2:
	match id:
		"mutation":
			return _shell_target("editor/expression")
		"competition":
			var ledger: Control = page.atlas._meme_ledger
			return _project(ledger._rows[_source_id].tag) if ledger._rows.has(_source_id) else _shell_target("sheet/map")
	return _shell_target(id)

func _shell_target(id: String) -> Rect2:
	var target: Variant = shell._target(id)
	return target if target is Rect2 else _project(target)

func _reserved_areas() -> Array[Rect2]:
	var result: Array[Rect2] = []
	result.assign(shell._tutorial_reserved_areas())
	return result
