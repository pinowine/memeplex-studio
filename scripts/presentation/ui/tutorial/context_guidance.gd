extends Node

const Tutorial = preload("res://scripts/presentation/ui/tutorial/tutorial.gd")
const LESSONS := {"fax":"LOC_GUIDANCE_FIRST_FAX", "competition":"LOC_GUIDANCE_FIRST_COMPETITOR", "mutation":"LOC_GUIDANCE_FIRST_MUTATION"}
var page: Node
var shell: Node
var mentor: Control
var enabled := true
var _lesson_id := ""
var _source_id := ""
var _drag_slip: Control
var _map_anchor: Control
var _fax_had_materials := false

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
	page.desk._fax.event_output_delivered.connect(_on_fax_delivered)

func set_enabled(value: bool) -> void:
	enabled = value
	if value: return
	for id: String in page.simulation.guidance_progress():
		page.simulation.mark_guidance_shown(id)
	close()

func close() -> void:
	if mentor == null: return
	mentor.skip()
	mentor.hide()
	page.desk._fax.cancel_material_drag()

func _record(id: String, source_id: String) -> void:
	page.simulation.queue_guidance(id, source_id)
	if not enabled: page.simulation.mark_guidance_shown(id)

func _on_fax_delivered(record: Dictionary, _paper: Control) -> void:
	_record("fax", str(record.get("instance_id", "")))

func observe_world(world: Dictionary) -> void:
	if page == null or page.simulation == null: return
	if page.simulation.guidance_progress().has("mutation"): return
	for variant: Dictionary in world.get("variants", []):
		if bool(variant.mutation):
			_record("mutation", str(variant.id))
			break

func _process(_delta: float) -> void:
	if mentor == null or not page._ready_to_run: return
	var progress: Dictionary = page.simulation.guidance_progress()
	var map_visible: bool = page.desk._active_sheet == "map" and not page.desk._stack.is_switching() and page.spread.is_visible_in_tree()
	if not progress.has("competition") and map_visible:
		for point: Dictionary in page.spread._screen_points:
			if not bool(point.visible) or str(point.pool) != "external": continue
			var variant: Dictionary = page.simulation.variant_by_id(str(point.variant_id))
			if not variant.is_empty() and str(variant.creator) != "player" and variant.origin_ids.is_empty():
				_record("competition", str(variant.id))
				break
	var blocked: bool = shell.main_mode or shell.main_menu.visible or shell.ending.visible or page.hud.modal_visible() or shell.tutorial._active or not page.startup_ready()
	if mentor._active:
		if _lesson_id == "fax" and _fax_had_materials and not page._event_has_pending_material(_source_id):
			close()
			return
		mentor.set_interaction_blocked(blocked)
		mentor.visible = enabled and not blocked
		mentor.set_process_input(mentor.visible)
		return
	if not enabled or blocked: return
	progress = page.simulation.guidance_progress()
	for id: String in ["fax", "competition", "mutation"]:
		if not progress.has(id) or bool(progress[id].shown): continue
		if id == "competition" and not map_visible: continue
		if id == "mutation" and (page.desk._revealed_focus != "sheet/edit" or str(page.desk._camera.inspection().state) != "focused"): continue
		_lesson_id = id
		_source_id = str(progress[id].source_id)
		if id == "mutation": page.hud.design_workbench()._detail_scroll.ensure_control_visible(page.hud.design_workbench()._final_expression)
		if not _target(id).has_area(): continue
		_fax_had_materials = id == "fax" and page._event_has_pending_material(_source_id)
		if id == "fax" and _unique_card_pending() and _drag_targets("fax").is_empty(): continue
		var steps: Array[Dictionary] = [{"id":id, "text":LESSONS[id], "action":"continue", "target":id, "contextual":true, "no_blur":true, "map_navigation":id == "competition", "contextual_drag":_fax_had_materials}]
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
			var target: Variant = shell._target("editor/expression")
			return target if target is Rect2 else _project(target)
		"competition":
			for point: Dictionary in page.spread._screen_points:
				if str(point.variant_id) != _source_id or not bool(point.visible): continue
				if not is_instance_valid(_map_anchor):
					_map_anchor = Control.new()
					_map_anchor.name = "MentorCompetitionTarget"
					_map_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
					page.atlas.map_input.add_child(_map_anchor)
				_map_anchor.position = page.atlas.map_input.get_global_transform_with_canvas().affine_inverse() * Vector2(point.screen_position) - Vector2(10, 10)
				_map_anchor.size = Vector2(20, 20)
				var area := _project(_map_anchor)
				if area.has_area(): return area
	return Rect2()

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
