extends Control

signal interface_language_requested(locale: String)

signal draft_publish_requested(draft: Dictionary)
signal country_selection_requested
signal speed_requested(value: int)
signal step_requested
signal workbench_requested
signal tools_requested
signal save_requested
signal load_requested
signal restart_requested
signal event_acknowledged
signal settings_requested
signal developer_requested
signal codex_requested
signal quit_requested
signal menu_close_requested
signal design_action_requested(action: String, params: Dictionary)
signal skill_purchase_requested(id: String)
signal material_tabletop_requested(kind: String, id: String)

const PaperStyle := preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const DesignWorkbench = preload("res://scripts/presentation/studio/workbench/desk_design_workbench.gd")

@onready var _workbench: PanelContainer = %Workbench
@onready var _kernel: OptionButton = %Kernel
@onready var _preset: OptionButton = %Preset
@onready var _language: OptionButton = %Language
@onready var _group: OptionButton = %Group
@onready var _channel: OptionButton = %Channel
@onready var _topic: OptionButton = %Topic
@onready var _permission: OptionButton = %ReusePermission
@onready var _slot_labels: Array[Label] = [%SlotLabel0, %SlotLabel1, %SlotLabel2, %SlotLabel3, %SlotLabel4]
@onready var _slot_edits: Array[LineEdit] = [%SlotEdit0, %SlotEdit1, %SlotEdit2, %SlotEdit3, %SlotEdit4]

var _screen_modals: Control
var _locale_catalog: Resource
var _interface_language: CheckButton
var _kernels: Array = []
var _presets: Array = []
var _slot_ids: PackedStringArray = []
var _last_state: Dictionary = {}
var _fullscreen := false
var _setting_draft := false
var _menu_mode := ""
var _date_rect := Rect2(22, 20, 216, 222)
var _setup_stage := "meme"
var _preset_target := ""
var _desk_plate := Rect2()
var _desk_controller: Control
var _design_workbench: Control
var _design_syncing := false
var _context_topic_ids := PackedStringArray()
var _design_metadata: Dictionary = {}
var _active_design_sheet := "edit"


func _ready() -> void:
	_install_interface_language()
	%SelectCountry.pressed.connect(func() -> void: country_selection_requested.emit())
	%Create.pressed.connect(func() -> void: workbench_requested.emit())
	%Tools.pressed.connect(func() -> void: tools_requested.emit())
	%Save.pressed.connect(func() -> void: save_requested.emit())
	%Load.pressed.connect(func() -> void: load_requested.emit())
	%Restart.pressed.connect(func() -> void: restart_requested.emit())
	%Codex.pressed.connect(func() -> void: codex_requested.emit())
	%Quit.pressed.connect(func() -> void: quit_requested.emit())
	%DeveloperClose.pressed.connect(func() -> void: menu_close_requested.emit())
	%CodexClose.pressed.connect(func() -> void: menu_close_requested.emit())
	%CodexList.item_selected.connect(_show_codex_entry)
	%Fullscreen.pressed.connect(_toggle_fullscreen)
	%Publish.pressed.connect(func() -> void: draft_publish_requested.emit(get_draft()))
	%Pause.pressed.connect(func() -> void: speed_requested.emit(0))
	%Speed1.pressed.connect(func() -> void: speed_requested.emit(1))
	%Speed2.pressed.connect(func() -> void: speed_requested.emit(2))
	%Step.pressed.connect(func() -> void: step_requested.emit())
	%Return.pressed.connect(func() -> void: workbench_requested.emit())
	%EventContinue.pressed.connect(func() -> void: event_acknowledged.emit())
	%EffectDetails.toggled.connect(func(expanded: bool) -> void: %ActualEffect.visible = expanded)
	%Recreate.pressed.connect(func() -> void: workbench_requested.emit())
	%ResultRestart.pressed.connect(func() -> void: restart_requested.emit())
	_kernel.item_selected.connect(_on_kernel_selected)
	_preset.item_selected.connect(_on_preset_selected)
	_group.item_selected.connect(_on_group_selected)
	for edit in _slot_edits:
		edit.text_changed.connect(func(_text: String) -> void: _refresh_preview())
	for permission_id in ["allowed", "conditional", "restricted", "unknown"]:
		var labels := {"allowed": "允许再利用", "conditional": "有条件许可", "restricted": "限制再利用", "unknown": "许可未知"}
		_permission.add_item(str(labels[permission_id]))
		_permission.set_item_metadata(_permission.item_count - 1, StringName(permission_id))
	%PoliticalKnown.toggled.connect(_on_political_known)
	_on_political_known(%PoliticalKnown.button_pressed)
	%EventCard.hide()
	%ResultCard.hide()
	%Instruments.hide()
	%History.show()
	_install_design_workbench()
	set_menu("")
	resized.connect(_layout_panels)
	_layout_panels()
	_refresh_preview()


func configure(catalog: MemeDemoCatalog) -> void:
	_locale_catalog = catalog
	_kernels = _values(catalog, "kernels")
	_presets = _values(catalog, "presets")
	# Prime only catalog-owned defaults; no draft or player buffer is rewritten.
	for preset in _presets:
		var defaults := PackedStringArray(_field(preset,"default_values",[]))
		var source_expression := DeskLocalization.source_join(" / ",defaults)
		DeskLocalization.source_format("%s：%s",[str(_field(preset,"title","")),source_expression],[0,1])
	_fill_codex()
	_fill_options(_kernel, _kernels)
	var groups: Array = _values(catalog, "groups")
	_fill_options(_group, groups)
	_fill_options(_channel, _values(catalog, "channels"))
	_fill_options(_topic, _values(catalog, "topics"))
	_select_id(_topic, "cost_of_living")
	var languages: Array = _values(catalog, "languages")
	if languages.is_empty():
		var seen: Dictionary = {}
		for group in groups:
			var language_id := str(_field(group, "language_id", ""))
			if not language_id.is_empty() and not seen.has(language_id):
				seen[language_id] = true
				languages.append({"id": language_id, "title": language_id})
	_fill_options(_language, languages)
	_on_kernel_selected(maxi(0, _kernel.selected))
	_on_group_selected(_group.selected)
	%Publish.disabled = _kernels.is_empty() or groups.is_empty() or _channel.item_count == 0
	_design_workbench.configure(catalog)
	_design_workbench.set_draft(get_draft())
	set_setup_stage("meme")


func _install_design_workbench() -> void:
	# Column 承载当前草稿字段，工作纸组件负责可见编辑界面。
	_workbench.get_node("Column").hide()
	# 隐藏字段仍参与当前草稿读写，禁止步长取整损失模块和语境效果的精度。
	for field: SpinBox in [%PoliticalX, %PoliticalY, %PragmaticX, %PragmaticY, %RemixCost, %ContextDependency, %LanguageAccess, %Recognizability]:
		field.step = 0.0
	_design_workbench = DesignWorkbench.new()
	_design_workbench.name = "DesignWorkbench"
	_workbench.add_child(_design_workbench)
	_design_workbench.bind_publish(%Publish, %PointCost)
	_design_workbench.draft_changed.connect(_apply_design_draft)
	_design_workbench.design_action_requested.connect(func(action: String, params: Dictionary) -> void: design_action_requested.emit(action, params))
	_design_workbench.skill_purchase_requested.connect(func(id: String) -> void: skill_purchase_requested.emit(id))
	_design_workbench.material_tabletop_requested.connect(func(kind: String,id: String) -> void: material_tabletop_requested.emit(kind,id))
	_design_workbench.sheet_requested.connect(func(id: String) -> void:
		if _desk_controller != null: _desk_controller.select_sheet(id)
	)
	%PointCost.hide()


func _apply_design_draft(draft: Dictionary) -> void:
	if _design_syncing: return
	_design_syncing = true
	set_draft(draft)
	_design_syncing = false


func report_design_errors(errors: PackedStringArray) -> void:
	_design_workbench.report_errors(errors)


func design_workbench() -> Control:
	return _design_workbench


func get_draft() -> Dictionary:
	var slots: Dictionary = {}
	for index in _slot_ids.size():
		slots[_slot_ids[index]] = DeskLocalization.edit_value(_slot_edits[index])
	var replaceable := PackedStringArray()
	for part in %Replaceable.text.replace("，", ",").split(",", false):
		var slot_id: String = str(part).strip_edges()
		if not slot_id.is_empty() and not replaceable.has(slot_id):
			replaceable.append(slot_id)
	var draft: Dictionary = {
		"kernel_id": _selected_id(_kernel), "preset_id": _selected_id(_preset), "slots": slots,
		"language_id": _selected_id(_language), "group_id": _selected_id(_group),
		"channel_id": _selected_id(_channel), "political_known": %PoliticalKnown.button_pressed,
		"topic_ids": PackedStringArray([_selected_id(_topic)]) if _topic.selected >= 0 else PackedStringArray(),
		"political_position": Vector2(%PoliticalX.value, %PoliticalY.value),
		"pragmatic_position": Vector2(%PragmaticX.value, %PragmaticY.value),
		"target": DeskLocalization.edit_value(%Target).strip_edges(), "replaceable_slots": replaceable,
		"remix_cost": %RemixCost.value, "context_dependency": %ContextDependency.value,
		"reuse_permission": StringName(_selected_id(_permission)),
		"language_access": %LanguageAccess.value, "recognizability": %Recognizability.value
	}
	if _design_metadata.has("context_layer_record"): draft.topic_ids=_context_topic_ids.duplicate()
	for key in _design_metadata: draft[key] = _design_metadata[key].duplicate(true)
	return draft


func set_draft(d: Dictionary) -> void:
	_setting_draft = true
	_context_topic_ids=PackedStringArray(d.get("topic_ids",[]))
	_design_metadata.clear()
	for key in ["context_layer_record", "module_patch_record", "skill_effects", "context_layer_attachment"]:
		if d.has(key) and (d[key] is Dictionary or d[key] is Array): _design_metadata[key] = d[key].duplicate(true)
	_select_id(_kernel, str(d.get("kernel_id", "")))
	_on_kernel_selected(maxi(0, _kernel.selected))
	_select_id(_preset, str(d.get("preset_id", "")))
	if not str(d.get("preset_id", "")).is_empty():
		_on_preset_selected(_preset.selected)
	var slots: Dictionary = d.get("slots", {})
	for index in _slot_ids.size():
		if slots.has(_slot_ids[index]):
			DeskLocalization.bind_edit(_slot_edits[index], str(slots[_slot_ids[index]]), false)
	_select_id(_language, str(d.get("language_id", "")))
	_select_id(_group, str(d.get("group_id", "")))
	_select_id(_channel, str(d.get("channel_id", "")))
	var topic_ids := PackedStringArray(d.get("topic_ids", ["cost_of_living"]))
	if not topic_ids.is_empty():
		_select_id(_topic, topic_ids[0])
	else:
		_topic.select(-1)
	_select_id(_permission, str(d.get("reuse_permission", "allowed")))
	%PoliticalKnown.button_pressed = bool(d.get("political_known", false))
	_on_political_known(%PoliticalKnown.button_pressed)
	var political: Vector2 = d.get("political_position", Vector2.ZERO)
	var pragmatic: Vector2 = d.get("pragmatic_position", Vector2.ZERO)
	%PoliticalX.value = political.x
	%PoliticalY.value = political.y
	%PragmaticX.value = pragmatic.x
	%PragmaticY.value = pragmatic.y
	DeskLocalization.bind_edit(%Target, str(d.get("target", "")), false)
	var replaceable: PackedStringArray = PackedStringArray(d.get("replaceable_slots", []))
	%Replaceable.text = ", ".join(replaceable)
	%RemixCost.value = float(d.get("remix_cost", 0.25))
	%ContextDependency.value = float(d.get("context_dependency", 0.4))
	%LanguageAccess.value = float(d.get("language_access", 0.8))
	%Recognizability.value = float(d.get("recognizability", 0.8))
	_setting_draft = false
	_refresh_preview()
	if _design_workbench != null: _design_workbench.set_draft(get_draft())


func show_workbench(visible: bool) -> void:
	show_sheet("edit" if visible else "map")


func show_sheet(id: String) -> void:
	if id in ["meme", "design"]: id = "edit"
	if id not in ["map", "edit", "cultivate", "spread"]: return
	_workbench.visible = id != "map"
	if id != "map":
		_active_design_sheet = id
		_design_workbench.set_active_sheet(id)
		%ResultCard.hide()
	if _desk_controller != null: _desk_controller.sheet_changed(id)
	%MapHintCard.visible = id == "map" and str(_last_state.get("phase", "draft")) == "draft"
	%Instruments.visible = false
	_refresh_modal()
	_layout_panels()


func set_setup_stage(stage: String) -> void:
	_setup_stage = stage
	%Publish.disabled = stage == "starter_call" or _kernels.is_empty() or _group.item_count == 0 or _channel.item_count == 0
	var initial := stage in ["meme", "country"]
	%Publish.text = "确认模因，选择投放国家" if initial else "确认表达并发布"
	%SelectCountry.text = "确认模因后选国" if initial else "选国／收起工作台"
	%Create.text = "返回修改模因" if stage == "country" else ("打印 / 创作" if _desk_plate.has_area() else "创建模因")
	%WorkbenchHint.text = "把收到的模因写成自己的表达，再选一处地方投放。" if initial else "写一份新版，让这句话继续走下去。"
	%MapHint.text = "02 / 模因已确认。点击地图选择投放国家，再点击下方“投放并进入游戏”。" if stage == "country" else "点击地图查看国家；翻开左侧稿纸继续创作。"
	if stage == "starter_call":
		%Publish.disabled = true
		%WorkbenchHint.text = "先接听 67；选一份起始表达，挂断后再动笔。"


func render(state: Dictionary) -> void:
	_last_state = state.duplicate(true)
	_design_workbench.sync_state(state)
	var phase := str(state.get("phase", "draft"))
	var country := DeskLocalization.text(str(state.get("country_title","尚未选国")))
	if country.is_empty():
		country = "尚未选国"
	%Date.text = DeskLocalization.format_text("%s  ·  模拟第 %d 小时", [country, int(state.get("hour", 0))])
	%Status.text = DeskLocalization.text(str(state.get("status", "创作准备")))
	%PointBalance.text = DeskLocalization.format_text("Meme 点数：%d", int(state.get("meme_points", 0)))
	%PointCost.hide()
	%Attention.text = DeskLocalization.format_text("注意力预算 %d  ·  玩家 %d / 外部 %d / 背景 %d", [int(state.get("attention_budget", 0)), int(state.get("attention_player", 0)), int(state.get("attention_external", 0)), int(state.get("attention_background", 0))])
	%MapHintCard.visible = phase == "draft" and not _workbench.visible
	%Metrics.text = DeskLocalization.format_text("曝光 %d  ·  采用 %d\n作者归属 %d  ·  来源影响 %d\n家族 %d  ·  版本 %d  ·  疲劳 %.2f", [
		int(state.get("exposed", 0)), int(state.get("adopted", 0)),
		int(state.get("owned_adopted", 0)), int(state.get("lineage_adopted", 0)),
		int(state.get("families", 0)), int(state.get("variants", 0)), float(state.get("fatigue", 0.0))])
	%Instruments.visible = phase in ["running", "event", "complete"] and not _workbench.visible
	%History.show()
	var blocked := phase != "running"
	for button in [%Pause, %Speed1, %Speed2, %Step]:
		button.disabled = blocked
	%Pause.button_pressed = int(state.get("speed", 0)) == 0
	%Speed1.button_pressed = int(state.get("speed", 0)) == 1
	%Speed2.button_pressed = int(state.get("speed", 0)) == 2
	if phase != "event":
		%EventCard.hide()
	if phase != "complete":
		%ResultCard.hide()
	%EventLog.clear()
	for event in state.get("events", []):
		var item_index: int = %EventLog.add_item(DeskLocalization.text(str(event.get("title", "事件"))))
		%EventLog.set_item_tooltip(item_index, DeskLocalization.format_text("%s\n%s\n67：%s\n执行详情：%s", [DeskLocalization.text(str(event.get("narrative", ""))), DeskLocalization.text(str(event.get("impact_text", ""))), DeskLocalization.text(str(event.get("mentor_comment", ""))), str(event.get("effect_text", "未提供作用记录"))]))
		PaperStyle.suppress_item_tooltip(%EventLog, item_index)
	%Lineage.clear()
	for variant in state.get("lineage", []):
		var ownership := DeskLocalization.text("玩家家族" if bool(variant.get("owned",false)) else "外部家族")
		var line := DeskLocalization.format_text("%s · %s · 偏移 %.2f", [str(variant.get("id", "")), ownership, float(variant.get("semantic_distance", 0.0))])
		var item_index: int = %Lineage.add_item(line)
		%Lineage.set_item_tooltip(item_index, DeskLocalization.format_text("家族：%s\n直接创作者：%s\n父版本：%s\n表达：%s\n源头：%s", [str(variant.get("family_id", "")), str(variant.get("creator", "")), str(variant.get("parent_ids", [])), str(variant.get("text", "")), str(variant.get("text", ""))]))
		PaperStyle.suppress_item_tooltip(%Lineage, item_index)
	var discoveries: Array = state.get("discoveries", [])
	%Discoveries.text = DeskLocalization.format_text("已收录：%s", (", ".join(PackedStringArray(discoveries)) if not discoveries.is_empty() else DeskLocalization.text("暂无")))
	%EconomyLog.clear()
	for entry in state.get("economy_log", []):
		%EconomyLog.add_item(str(entry))
	_refresh_modal()
	if _desk_controller != null:
		_desk_controller.sync_state(state)
		_layout_panels()


func show_event(event: Dictionary) -> void:
	%EventTitle.text = DeskLocalization.text(str(event.get("title", "传播事件")))
	%EventOrigin.text = "%s / %s" % [str(event.get("origin", "")), str(event.get("definition_id", ""))]
	%Narrative.text = DeskLocalization.text(str(event.get("narrative", "没有提供叙事文本。")))
	%ImpactSummary.text = DeskLocalization.text(str(event.get("impact_text", "")))
	%MentorComment.text = "67：" + DeskLocalization.text(str(event.get("mentor_comment", DeskLocalization.text("先看清消息的出处，再决定要不要发声。"))))
	%ActualEffect.text = "\n".join(DeskLocalization.lines(Array(str(event.get("effect_text","没有提供实际作用记录。")).split("\n"))))
	%ActualEffect.hide()
	%EffectDetails.button_pressed = false
	%EventCard.visible = _desk_controller == null
	%EventContinue.disabled = _desk_controller != null
	_refresh_modal()
	if _desk_controller != null: _desk_controller.receive_event(event)


func dismiss_fax() -> void:
	%EventCard.hide()
	_refresh_modal()


func show_result(result: Dictionary) -> void:
	%ResultTitle.text = DeskLocalization.text(str(result.get("title", "本轮观察完成")))
	var final_state: Dictionary = _last_state.duplicate(true)
	final_state.merge(result, true)
	%ResultSummary.text = DeskLocalization.format_text("观察至第 %d 游戏小时 · 合成样本\n曝光 %d · 采用 %d\n作者归属 %d · 来源影响 %d\n家族 %d · 版本 %d\nMeme 点数余额 %d\n注意力预算 %d = 玩家 %d + 外部 %d + 背景 %d", [
		int(final_state.get("hour", 0)), int(final_state.get("exposed", 0)), int(final_state.get("adopted", 0)),
		int(final_state.get("owned_adopted", 0)), int(final_state.get("lineage_adopted", 0)),
		int(final_state.get("families", 0)), int(final_state.get("variants", 0)), int(final_state.get("meme_points", 0)),
		int(final_state.get("attention_budget", 0)), int(final_state.get("attention_player", 0)),
		int(final_state.get("attention_external", 0)), int(final_state.get("attention_background", 0))])
	var summary := str(result.get("summary", result.get("text", "")))
	if not summary.is_empty():
		%ResultSummary.text += "\n" + summary
	%ResultCard.visible = _desk_controller == null
	%EventCard.hide()
	show_workbench(false)
	_refresh_modal()


func inspection() -> Dictionary:
	return {
		"workbench_visible": _workbench.visible, "active_design_sheet":_active_design_sheet, "fullscreen": _fullscreen,
		"setup_stage": _setup_stage,
		"menu_mode": _menu_mode, "modal_visible": modal_visible(),
		"shade_visible": %ModalShade.visible, "shade_mouse_filter": %ModalShade.mouse_filter,
		"history_rect": %History.get_global_rect(), "event_rect": %EventCard.get_global_rect(),
		"create_rect": %Create.get_global_rect(), "point_balance_rect": %PointBalance.get_global_rect(),
		"legend_count": %Legend.item_count, "codex_count": %CodexList.item_count,
		"codex_details": %CodexDetails.text,
		"event_visible": %EventCard.visible, "result_visible": %ResultCard.visible,
		"map_hint_visible": %MapHintCard.visible, "point_cost_text": %PointCost.text,
		"result_summary_text": %ResultSummary.text,
		"narrative_text": %Narrative.text, "effect_text": %ActualEffect.text,
		"impact_text": %ImpactSummary.text, "mentor_text": %MentorComment.text,
		"effect_details_visible": %ActualEffect.visible,
		"narrative_node": str(%Narrative.get_path()), "effect_node": str(%ActualEffect.get_path()),
		"slot_count": _slot_ids.size(), "prebuilt_slot_count": _slot_edits.size(),
		"preset_count": _presets.size(), "preset_options": _preset.item_count,
		"preset_source_text": %PresetSource.text,
		"root_mouse_filter": mouse_filter, "event_count": %EventLog.item_count,
		"lineage_count": %Lineage.item_count, "sample_label": %SampleLabel.text,
		"point_balance_text": %PointBalance.text, "attention_text": %Attention.text,
		"economy_log_count": %EconomyLog.item_count, "purchase_disabled": %Purchase.disabled,
		"phase": str(_last_state.get("phase", "draft")), "draft": get_draft(),
		"design_workbench":_design_workbench.inspection() if _design_workbench != null else {},
		"draft_fields_visible":_workbench.get_node("Column").visible
	}


func set_menu(mode: String) -> void:
	if mode not in ["", "settings", "developer", "codex"]:
		push_error("Unknown demo menu: " + mode)
		return
	_menu_mode = mode
	%SettingsMenu.visible = mode == "settings"
	%DeveloperMenu.visible = mode == "developer"
	%CodexPanel.visible = mode == "codex"
	%DeveloperStatus.text = DeskLocalization.format_text("当前内容：%d 个案例预设；事件工具仅修改开发内容副本。", _presets.size())
	_refresh_modal()
	if mode == "settings":
		%Save.grab_focus()
	elif mode == "developer":
		%Tools.grab_focus()
	elif mode == "codex":
		%CodexList.grab_focus()
	elif %EventCard.visible:
		%EventContinue.grab_focus()


func menu_mode() -> String:
	return _menu_mode


func modal_visible() -> bool:
	return not _menu_mode.is_empty() or %EventCard.visible or %ResultCard.visible


func show_codex() -> void:
	set_menu("codex")
	if %CodexList.item_count > 0 and %CodexList.get_selected_items().is_empty():
		%CodexList.select(0)
		_show_codex_entry(0)


func layout_for_date(date_rect: Rect2) -> void:
	_date_rect = Rect2(date_rect.position - global_position, date_rect.size)
	_layout_panels()


func configure_desk(plate_rect: Rect2, controller: Control = null) -> void:
	_desk_plate = plate_rect
	_desk_controller = controller
	if get_parent().get_parent().has_meta("studio3d"):
		_install_screen_modals()
	_layout_panels()


func set_legend(rows: Array[Dictionary]) -> void:
	%Legend.clear()
	for row in rows:
		var kind := str(row.get("kind", "appearance"))
		var marker := "●" if kind == "adoption" else "○"
		var index: int = %Legend.add_item("%s %s" % [marker, DeskLocalization.text(str(row.get("title", row.get("id", "模因"))))])
		%Legend.set_item_metadata(index, row.duplicate(true))
		var color: Variant = row.get("color", Color(0.28, 0.25, 0.2))
		if color is Color:
			%Legend.set_item_custom_fg_color(index, color)
		%Legend.set_item_tooltip(index, DeskLocalization.format_text("ID：%s\n标记：%s\n范围：%s\n%s", [str(row.get("id", "")), kind, str(row.get("scope", "")), %LegendNote.text]))
		PaperStyle.suppress_item_tooltip(%Legend, index)
	%LegendEmpty.visible = rows.is_empty()


func _refresh_modal() -> void:
	%ModalShade.visible = modal_visible()
	%Create.disabled = modal_visible()
	%EventContinue.disabled = not _menu_mode.is_empty() or (_desk_controller != null and not _desk_controller.event_ready())
	%EffectDetails.disabled = not _menu_mode.is_empty()
	# The same shade intercepts the event card while a menu is above it.
	if not _menu_mode.is_empty():
		%ModalShade.z_index = 29
		%ModalShade.move_to_front()
		%SettingsMenu.move_to_front()
		%DeveloperMenu.move_to_front()
		%CodexPanel.move_to_front()
	else:
		%ModalShade.z_index = 10
		var index := mini(%EventCard.get_index(), %ResultCard.get_index())
		if %ModalShade.get_index() < index: index -= 1
		%ModalShade.get_parent().move_child(%ModalShade, index)


func _layout_panels() -> void:
	if not is_node_ready():
		return
	var viewport_size := size if size.x > 0 and size.y > 0 else get_viewport_rect().size
	if _desk_plate.has_area():
		_layout_desk(viewport_size)
		return
	var history_left := _date_rect.position.x
	var history_top := _date_rect.end.y + 12.0
	%History.position = Vector2(history_left, history_top)
	%History.size = Vector2(maxf(300.0, _date_rect.size.x), minf(270.0, maxf(140.0, viewport_size.y - 286.0 - history_top)))
	%Instruments.offset_left = history_left
	%Instruments.offset_right = history_left + 572.0
	var paper_left := maxf(_date_rect.end.x, history_left + %History.size.x) + 18.0
	var paper_right := maxf(paper_left + 440.0, viewport_size.x - 430.0)
	if not _fullscreen:
		paper_right = minf(paper_right, paper_left + 540.0)
	_workbench.offset_left = paper_left
	_workbench.offset_right = paper_right
	%MapHintCard.offset_left = paper_left
	%MapHintCard.offset_right = minf(paper_left + 480.0, paper_right)


func _desk_place(node: Control, rect: Rect2) -> void:
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.position = rect.position
	node.size = rect.size


func _layout_desk(_view: Vector2) -> void:
	for panel in [%History, %Instruments, %MapHintCard, %ResultCard, get_node("QuickActions"), get_node("LegendPanel")]: panel.hide()
	if _desk_controller == null: _desk_place(_workbench, _desk_plate)
	if _screen_modals == null:
		_desk_place(%CodexPanel, Rect2(_desk_plate.position, _desk_plate.size))
	else:
		layout_screen_modals()


func _install_screen_modals() -> void:
	if _screen_modals != null: return
	# These menus use viewport pixels; desk sheets keep their camera-following canvas.
	var layer := CanvasLayer.new()
	layer.name = "ScreenSpaceMenus"
	layer.layer = 60
	add_child(layer)
	_screen_modals = Control.new()
	_screen_modals.name = "MenuLayout"
	_screen_modals.theme = theme
	_screen_modals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_screen_modals)
	_screen_modals.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	for panel: Control in [%ModalShade,%EventCard,%ResultCard,%SettingsMenu,%DeveloperMenu,%CodexPanel]:
		panel.reparent(_screen_modals,false)
	%ModalShade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout_screen_modals()
	_refresh_modal()


func layout_screen_modals() -> void:
	if _screen_modals == null: return
	var view := get_viewport_rect().size
	_screen_modals.position = Vector2.ZERO
	_screen_modals.size = view
	var available := (view-Vector2(96,96)).max(Vector2(1,1))
	for panel: Control in [%SettingsMenu,%DeveloperMenu,%CodexPanel]:
		var desired := Vector2(600,650)
		if panel == %CodexPanel: desired = view-Vector2(192,144)
		var dimensions := desired.max(panel.get_combined_minimum_size()).min(available)
		_desk_place(panel,Rect2((view-dimensions)*.5,dimensions))


func _fill_codex() -> void:
	%CodexList.clear()
	for preset in _presets:
		var index: int = %CodexList.add_item(DeskLocalization.text(str(_field(preset, "title", _field(preset, "id", "表达")))))
		%CodexList.set_item_metadata(index, preset)
		%CodexList.set_item_tooltip(index, "%s / %s" % [DeskLocalization.text(str(_field(preset, "title", ""))), DeskLocalization.text("收录的表达")])
		PaperStyle.suppress_item_tooltip(%CodexList, index)
	%CodexDetails.text = "这里收着一些曾经流传的表达。"
	if %CodexList.item_count > 0:
		%CodexList.select(0)
		_show_codex_entry(0)


func _show_codex_entry(index: int) -> void:
	if index < 0 or index >= %CodexList.item_count:
		return
	var preset: Variant = %CodexList.get_item_metadata(index)
	var slot_ids := PackedStringArray(_field(preset, "required_slots", []))
	var prompts := PackedStringArray(_field(preset, "slot_prompts", []))
	var values := PackedStringArray(_field(preset, "default_values", []))
	var slots := PackedStringArray()
	for slot_index in slot_ids.size():
		var prompt: String = DeskLocalization.text(prompts[slot_index]) if slot_index < prompts.size() else slot_ids[slot_index]
		var value: String = DeskLocalization.text(values[slot_index]) if slot_index < values.size() else ""
		slots.append("%s: %s" % [DeskLocalization.text(prompt), DeskLocalization.text(value)])
	%CodexDetails.text = "%s\n\n%s" % [DeskLocalization.text(str(_field(preset, "title", ""))), "\n".join(slots)]


func _on_kernel_selected(index: int) -> void:
	if index < 0 or index >= _kernels.size():
		return
	var kernel: Variant = _kernels[index]
	if not _preset_target.is_empty() and DeskLocalization.edit_value(%Target) == _preset_target:
		DeskLocalization.bind_edit(%Target,"",false)
	_preset_target = ""
	_slot_ids = PackedStringArray(_field(kernel, "required_slots", []))
	var prompts := PackedStringArray(_field(kernel, "slot_prompts", []))
	var defaults := PackedStringArray(_field(kernel, "default_values", []))
	for slot_index in _slot_edits.size():
		var enabled := slot_index < _slot_ids.size()
		_slot_edits[slot_index].visible = enabled
		_slot_labels[slot_index].visible = enabled
		if enabled:
			_slot_labels[slot_index].text = prompts[slot_index] if slot_index < prompts.size() else _slot_ids[slot_index]
			DeskLocalization.bind_edit(_slot_edits[slot_index],defaults[slot_index] if slot_index < defaults.size() else "",true)
	%KernelDescription.text = str(_field(kernel, "description", ""))
	%Replaceable.text = ", ".join(_slot_ids)
	_fill_preset_options(str(_field(kernel, "id", "")))
	%PresetSource.text = "自定义结构：未选择案例来源。来源不等于素材许可；参数仍由玩家设定。"
	_refresh_preview()


func _fill_preset_options(kernel_id: String) -> void:
	_preset.clear()
	_preset.add_item("自定义 · 基模默认结构")
	_preset.set_item_metadata(0, "")
	for preset in _presets:
		if str(_field(preset, "kernel_id", "")) != kernel_id:
			continue
		_preset.add_item(DeskLocalization.text(str(_field(preset, "title", ""))))
		_preset.set_item_metadata(_preset.item_count - 1, str(_field(preset, "id", "")))
	_preset.select(0)


func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= _preset.item_count:
		return
	var preset_id := str(_preset.get_item_metadata(index))
	if preset_id.is_empty():
		_on_kernel_selected(_kernel.selected)
		return
	for preset in _presets:
		if str(_field(preset, "id", "")) != preset_id:
			continue
		# Offer an editable default without replacing the player's chosen object.
		if DeskLocalization.edit_value(%Target).strip_edges().is_empty() or DeskLocalization.edit_value(%Target) == _preset_target:
			_preset_target = str(_field(preset, "title", ""))
			DeskLocalization.bind_edit(%Target,_preset_target,true)
		var defaults := PackedStringArray(_field(preset, "default_values", []))
		var prompts := PackedStringArray(_field(preset, "slot_prompts", []))
		for slot_index in _slot_ids.size():
			DeskLocalization.bind_edit(_slot_edits[slot_index],defaults[slot_index],true)
			_slot_labels[slot_index].text = prompts[slot_index]
		%Replaceable.text = ", ".join(_slot_ids)
		%PresetSource.text = DeskLocalization.format_text("%s\n来源：%s\nSHA-256：%s\n文档：%s\n家族锚点：%s\n%s", [str(_field(preset, "source_case_id", "")), str(_field(preset, "source_path", "")), str(_field(preset, "source_sha256", "")), str(_field(preset, "source_document_path", "")), str(_field(preset, "family_anchor", "")), str(_field(preset, "context_hint", ""))])
		_refresh_preview()
		return


func _on_group_selected(index: int) -> void:
	if _setting_draft or index < 0:
		return
	var item: Variant = _group.get_item_metadata(index)
	if item is Dictionary:
		_select_id(_language, str(item.get("language_id", "")))
	elif item is Resource:
		_select_id(_language, str(_field(item, "language_id", "")))


func _on_political_known(known: bool) -> void:
	%PoliticalX.editable = known
	%PoliticalY.editable = known


func _toggle_fullscreen() -> void:
	_fullscreen = not _fullscreen
	%Fullscreen.text = "还原半页" if _fullscreen else "展开纸页"
	_layout_panels()


func _refresh_preview() -> void:
	if _setting_draft:
		return
	var parts := PackedStringArray()
	for index in _slot_ids.size():
		parts.append(_slot_edits[index].text.strip_edges())
	%Preview.text = "。".join(parts) if not parts.is_empty() else "选择基模，填写槽位，形成具体表达。"
	if _design_workbench != null and not _design_syncing: _design_workbench.set_draft(get_draft())


func _fill_options(option: OptionButton, values: Array) -> void:
	option.clear()
	for item in values:
		var title: String = str(item) if item is String or item is StringName else DeskLocalization.text(str(_field(item, "title", _field(item, "id", ""))))
		option.add_item(title)
		option.set_item_metadata(option.item_count - 1, item)
	if option.item_count > 0:
		option.select(0)


func _selected_id(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	var item: Variant = option.get_item_metadata(option.selected)
	return str(_field(item, "id", "")) if item is Resource or item is Dictionary else str(item)


func _select_id(option: OptionButton, id: String) -> void:
	for index in option.item_count:
		var item: Variant = option.get_item_metadata(index)
		var item_id := str(_field(item, "id", "")) if item is Resource or item is Dictionary else str(item)
		if item_id == id:
			option.select(index)
			return
	# Empty layers must not inherit a stale selection from the hidden form.
	option.select(-1)


func _field(item: Variant, key: String, fallback: Variant = null) -> Variant:
	if item is Dictionary:
		return item.get(key, fallback)
	if item is Object:
		for property in item.get_property_list():
			if str(property.name) == key:
				var value: Variant = item.get(key)
				return fallback if value == null else value
	return fallback


func _values(catalog: Resource, key: String) -> Array:
	var value: Variant = _field(catalog, key, [])
	if value is PackedStringArray:
		return Array(value)
	return value if value is Array else []

func _install_interface_language() -> void:
	var row := HBoxContainer.new()
	row.name = "InterfaceLanguageRow"
	var caption := Label.new()
	caption.text = "界面语言"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	_interface_language = CheckButton.new()
	_interface_language.name = "InterfaceLanguage"
	_interface_language.text = "English"
	_interface_language.set_pressed_no_signal(TranslationServer.get_locale().begins_with("en"))
	row.add_child(_interface_language)
	%SettingsMenu.get_node("Column").add_child(row)
	%SettingsMenu.get_node("Column").move_child(row,2)
	_interface_language.toggled.connect(func(enabled: bool): interface_language_requested.emit("en" if enabled else "zh_CN"))
	for edit: LineEdit in _slot_edits: edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	%Target.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	%Preview.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED

func refresh_localization() -> void:
	if not is_node_ready(): return
	if _interface_language != null: _interface_language.set_pressed_no_signal(TranslationServer.get_locale().begins_with("en"))
	DeskLocalization.refresh_edits(self)
	if _locale_catalog != null:
		for option: OptionButton in [_kernel,_preset,_group,_channel,_topic,_language]:
			for index in option.item_count:
				var item: Variant = option.get_item_metadata(index)
				var source: String = str(item) if item is String or item is StringName else str(_field(item,"title",_field(item,"id","")))
				option.set_item_text(index,DeskLocalization.text(source))
		var selected_codex: PackedInt32Array = %CodexList.get_selected_items()
		_fill_codex()
		if not selected_codex.is_empty() and selected_codex[0] < %CodexList.item_count:
			%CodexList.select(selected_codex[0])
			_show_codex_entry(selected_codex[0])
	_refresh_preview()
	_layout_panels()
