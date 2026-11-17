extends Node

const Tutorial = preload("res://scripts/presentation/ui/tutorial/tutorial.gd")
const LESSONS := {"fax":"LOC_GUIDANCE_FIRST_FAX", "competition":"LOC_GUIDANCE_FIRST_COMPETITOR", "mutation":"LOC_GUIDANCE_FIRST_MUTATION"}
const EMOTIONS := {"fax":"friendly", "competition":"concerned", "mutation":"curious"}
var page: Node
var shell: Node
var mentor: Control
var enabled := true
var _lesson_id := ""
var _source_id := ""
var _drag_slip: Control
var _fax_had_materials := false
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
	mentor.set_drag_target_provider(_drag_targets)
	mentor.set_input_target_provider(shell._tutorial_input_targets, shell._tutorial_input_contains)
	mentor.drag_cancelled.connect(func(): page.desk._fax.cancel_material_drag())
	mentor.step_changed.connect(func(id: String, _step: Dictionary):
		if id == "mutation":
			var editor: Control = page.hud.design_workbench()
			editor._detail_scroll.ensure_control_visible.call_deferred(editor._final_expression))
	page.desk._fax.event_output_delivered.connect(_on_fax_delivered)

func set_enabled(value: bool) -> void:
	enabled = value
	if value: return
	if page.simulation.guidance_progress().has("fax"): page.simulation.mark_guidance_shown("fax")
	if _lesson_id == "fax": close()

func close() -> void:
	if mentor == null: return
	mentor.skip()
	mentor.hide()
	page.desk._fax.cancel_material_drag()

func _record(id: String, source_id: String) -> void:
	page.simulation.queue_guidance(id, source_id)
	if not enabled and id == "fax": page.simulation.mark_guidance_shown(id)

func _on_fax_delivered(record: Dictionary, _paper: Control) -> void:
	_record("fax", str(record.get("instance_id", "")))

func observe_world(world: Dictionary) -> void:
	if page == null or page.simulation == null: return
	if _world_seed != int(world.world_seed):
		_world_seed = int(world.world_seed)
		_seen_mutations.clear()
		_mutation_queue.clear()
	for variant: Dictionary in world.get("variants", []):
		var raw: Dictionary = page.simulation.variant_by_id(str(variant.id))
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
		if _lesson_id == "fax" and _fax_had_materials and not page._event_has_pending_material(_source_id):
			close()
			return
		mentor.set_interaction_blocked(blocked)
		mentor.visible = (enabled or _lesson_id in ["mutation", "competition"]) and not blocked
		mentor.set_process_input(mentor.visible)
		return
	if blocked: return
	progress = page.simulation.guidance_progress()
	for id: String in ["mutation", "fax", "competition"]:
		if not enabled and id == "fax": continue
		if id == "mutation":
			if _mutation_queue.is_empty(): continue
		elif not progress.has(id) or bool(progress[id].shown): continue
		_lesson_id = id
		_source_id = _mutation_queue[0] if id == "mutation" else str(progress[id].source_id)
		if id == "mutation": page.hud.design_workbench()._select_variant(_source_id)
		_fax_had_materials = id == "fax" and page._event_has_pending_material(_source_id)
		if id == "fax" and _unique_card_pending() and _drag_targets("fax").is_empty(): continue
		var steps: Array[Dictionary] = [{"id":id, "text":LESSONS[id], "emotion":EMOTIONS[id], "action":"continue", "target":id, "contextual":true, "no_blur":true, "map_navigation":id == "competition", "contextual_drag":_fax_had_materials}]
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
		mentor.configure(steps, _target, _reserved_areas)
		mentor.set_interaction_blocked(false)
		mentor.set_process_input(true)
		mentor.begin()
		page.simulation.mark_guidance_shown(id)
		break

func _project(control: Control) -> Rect2:
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return Rect2()
	return shell._tutorial_project_rect(control).intersection(mentor.get_viewport().get_visible_rect())

func _fax_slip() -> Control:
	if is_instance_valid(_drag_slip) and str(_drag_slip.record.get("instance_id", "")) == _source_id and _drag_slip.is_visible_in_tree() and not _drag_slip._committed and (_drag_slip.can_collect() or _drag_slip._pressed or _drag_slip.is_dragging()): return _drag_slip
	for slip: Control in page.desk._fax.material_slips():
		if str(slip.record.get("instance_id", "")) == _source_id and slip.can_collect():
			_drag_slip = slip
			return slip
	return null

func _unique_card_pending() -> bool:
	for record: Dictionary in page.simulation.event_materials():
		if str(record.instance_id) == _source_id and not bool(record.requested) and str(record.kind) in ["language", "group", "topic", "module"]: return true
	return false

func _target(id: String) -> Rect2:
	match id:
		"fax":
			var slip := _fax_slip()
			if slip != null and slip._face == null: return _project(slip)
			return _project(page.desk._fax._output.page_for_event(_source_id))
		"mutation":
			return _shell_target("editor/expression")
		"competition":
			var ledger: Control = page.atlas._meme_ledger
			return _project(ledger._rows[_source_id].tag) if ledger._rows.has(_source_id) else _shell_target("sheet/map")
	return _shell_target(id)

func _shell_target(id: String) -> Rect2:
	var target: Variant = shell._target(id)
	return target if target is Rect2 else _project(target)

func _drag_targets(id: String) -> Dictionary:
	if id != "fax": return {}
	var slip := _fax_slip()
	if slip == null or slip._face == null or str(slip.record.kind) not in ["language", "group", "topic", "module"]: return {}
	var source := _project(slip._face)
	var target: Variant = shell._target("desktop/stack/" + str(slip.record.kind))
	var area: Rect2 = target if target is Rect2 else _project(target)
	area = area.intersection(mentor.get_viewport().get_visible_rect())
	if not source.has_area() or not area.has_area(): return {}
	return {"source":source, "source_point":source.get_center(), "target":area, "dragging":slip.is_dragging()}

func _reserved_areas() -> Array[Rect2]:
	var result: Array[Rect2] = []
	result.assign(shell._tutorial_reserved_areas())
	if _lesson_id == "fax":
		var paper := _target("fax")
		if paper.has_area(): result.append(paper)
	return result
