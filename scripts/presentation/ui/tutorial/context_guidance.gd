extends Node

const Tutorial = preload("res://scripts/presentation/ui/tutorial/tutorial.gd")
const LESSON_ORDER := ["deviation", "mutation", "competition"]
const LESSONS := {"deviation":"LOC_GUIDANCE_DEVIATION", "competition":"LOC_GUIDANCE_FIRST_COMPETITOR", "mutation":"LOC_GUIDANCE_FIRST_MUTATION"}
const EMOTIONS := {"deviation":"concerned", "competition":"concerned", "mutation":"curious"}
var page: Node
var shell: Node
var mentor: Control
var enabled := true
var _source_id := ""

func configure(owner_shell: Node) -> void:
	shell = owner_shell
	page = shell.page
	mentor = Tutorial.new()
	mentor.name = "ContextMentor67"
	shell.add_child(mentor)
	mentor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mentor.set_input_target_provider(shell._tutorial_input_targets, shell._tutorial_input_contains)
	mentor.overview_requested.connect(page._return_to_desktop)
	mentor.step_changed.connect(func(id: String, _step: Dictionary):
		if id == "mutation":
			var editor: Control = page.hud.design_workbench()
			editor._detail_scroll.ensure_control_visible.call_deferred(editor._final_expression))

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled: close()

func close() -> void:
	if mentor == null: return
	mentor.skip()
	mentor.hide()

func observe_world(world: Dictionary) -> void:
	if page == null or page.simulation == null: return
	var progress: Dictionary = page.simulation.guidance_progress()
	if progress.has("deviation") and progress.has("mutation") and progress.has("competition"): return
	for variant: Dictionary in world.get("variants", []):
		var raw: Dictionary = page.simulation.variant_by_id(str(variant.id))
		if not progress.has("deviation"):
			var current: Dictionary = page.simulation.Lifecycle.content(raw)
			if bool(current.get("controlled", false)) and page.simulation.Deviation.total(raw.deviation_anchor, current) > .1:
				page.simulation.queue_guidance("deviation", str(raw.id))
		if str(raw.creator) == "player": continue
		var lesson := "competition" if raw.get("origin_ids", []).is_empty() else "mutation"
		if not progress.has(lesson): page.simulation.queue_guidance(lesson, str(raw.id))

func _process(_delta: float) -> void:
	if mentor == null or not page._ready_to_run: return
	var progress: Dictionary = page.simulation.guidance_progress()
	if not enabled:
		for id: String in LESSON_ORDER:
			if progress.has(id) and not bool(progress[id].shown): page.simulation.mark_guidance_shown(id)
		return
	var blocked: bool = shell.blocks_input() or page.hud.modal_visible() or shell.tutorial._active or not page.startup_ready()
	if mentor._active:
		mentor.set_interaction_blocked(blocked)
		mentor.visible = not blocked
		mentor.set_process_input(mentor.visible)
		return
	if blocked: return
	for id: String in LESSON_ORDER:
		if not progress.has(id) or bool(progress[id].shown): continue
		_source_id = str(progress[id].source_id)
		if id == "mutation": page.hud.design_workbench()._select_variant(_source_id)
		var steps: Array[Dictionary] = [{"id":id, "text":LESSONS[id], "emotion":EMOTIONS[id], "action":"continue", "target":id, "contextual":true, "no_blur":true}]
		var camera: Dictionary = page.desk._camera.inspection()
		var destination := {"deviation":"crt", "mutation":"sheet/edit", "competition":"sheet/map"}
		if str(camera.target) != str(destination[id]):
			var navigation := {"id":id+"_navigate", "text":"LOC_GUIDANCE_"+id.to_upper()+"_NAVIGATE", "emotion":EMOTIONS[id], "contextual":true, "no_blur":true}
			if id == "deviation":
				navigation.merge({"action":"component_focused", "match":{"id":"monitor"}, "target":"desktop/monitor"})
			else:
				var sheet := "edit" if id == "mutation" else "map"
				navigation.merge({"action":"sheet_selected", "match":{"id":sheet}, "target":"sheet/"+sheet})
			steps.push_front(navigation)
			if str(camera.state) != "overview":
				steps.push_front({"id":id+"_overview", "text":"LOC_GUIDANCE_RETURN_TO_DESK", "emotion":EMOTIONS[id], "action":"overview_returned", "contextual":true, "no_blur":true})
		if id == "mutation":
			steps[-1].target = "editor/expression"
			steps[-1].scroll = true
			var raw: Dictionary = page.simulation.variant_by_id(_source_id)
			var change_text: String = page.hud.design_workbench().community_change_text(raw)
			var key := "LOC_GUIDANCE_MUTATION_SPLIT" if not bool(raw.get("effective_content", raw).get("owned", raw.owned)) else "LOC_GUIDANCE_MUTATION_EFFECT"
			steps[-1].text = DeskLocalization.format_text(key, change_text)
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
