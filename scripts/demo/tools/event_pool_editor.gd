extends PanelContainer

signal closed

@export_dir var edit_directory: String = "res://content/demo/events"

const ORIGINS := ["world", "transmission", "environment_meme"]
const TRIGGERS := ["threshold", "scheduled", "random", "periodic"]
const DECAYS := ["constant", "linear", "exponential", "periodic"]
const CONDITION_FIELDS := ["hour", "exposed", "adopted", "variants", "families", "fatigue"]
const OPERATORS := ["ge", "gt", "le", "lt", "eq"]
const EFFECT_IDS := ["attention", "adoption", "trust", "fatigue", "remix", "semantic_shift", "channel_reach", "revival"]
const DESIGN_RULES = preload("res://content/demo/design_rules.tres")
const REWARD_KINDS := ["module", "solute", "solvent"]

var _catalog: MemeDemoCatalog
var _entries: Array[MemeDemoEvent] = []
var _draft: MemeDemoEvent
var _drafts: Dictionary = {}
var _selected_index: int = -1
var _condition_index: int = -1
var _effect_index: int = -1
var _loading: bool = false
var _last_errors := PackedStringArray()
var _reward_index := -1
var _reward_loading := false
var _rewards: ItemList
var _reward_kind: OptionButton
var _reward_item: OptionButton
var _reward_count: SpinBox
var _reward_tab: VBoxContainer
var _reward_remove: Button

func _ready() -> void:
	_build_reward_editor()
	_fill_options(%Origin, ORIGINS)
	_fill_options(%TriggerMode, TRIGGERS)
	_fill_options(%DecayModel, DECAYS)
	_fill_options(%ConditionField, CONDITION_FIELDS)
	_fill_options(%ConditionOperator, OPERATORS)
	_fill_options(%EffectId, EFFECT_IDS)
	%Search.text_changed.connect(func(_text: String): _refresh_list())
	%EventList.item_selected.connect(_on_event_selected)
	%Create.pressed.connect(create_event)
	%Duplicate.pressed.connect(duplicate_selected)
	%Close.pressed.connect(func(): closed.emit())
	%Save.pressed.connect(save_selected)
	%SaveCatalog.pressed.connect(save_catalog)
	%Reload.pressed.connect(reload_selected)
	%Conditions.item_selected.connect(_on_condition_selected)
	%Effects.item_selected.connect(_on_effect_selected)
	%AddCondition.pressed.connect(add_condition)
	%RemoveCondition.pressed.connect(remove_condition)
	%AddEffect.pressed.connect(add_effect)
	%RemoveEffect.pressed.connect(remove_effect)
	%Errors.item_selected.connect(_focus_error)
	for name in ["EventId", "EventTitle", "Topics", "Operations", "ExternalPreset", "Discoveries", "EvidenceStatus", "EffectGroups"]:
		get_node("%" + name).text_changed.connect(func(_text: String): _sync_draft())
	%Narrative.text_changed.connect(_sync_draft)
	%MentorComment.text_changed.connect(_sync_draft)
	for name in ["Origin", "TriggerMode", "DecayModel", "ConditionField", "ConditionOperator", "EffectId"]:
		get_node("%" + name).item_selected.connect(func(_index: int): _sync_draft())
	for name in ["StartHour", "Weight", "Chance", "Cooldown", "MaxOccurrences", "PhysicalDuration", "AttentionDuration", "DecayParameter", "ConditionValue", "EffectAmount", "EffectDuration"]:
		get_node("%" + name).value_changed.connect(func(_value: float): _sync_draft())
	_refresh_list()
	if not _entries.is_empty():
		_select_index(0)
	else:
		_refresh_form()

func configure(catalog: Resource) -> void:
	_catalog = catalog.duplicate(false) as MemeDemoCatalog if catalog != null else null
	if _catalog != null:
		_catalog.events = (catalog as MemeDemoCatalog).events.duplicate()
	_entries.clear()
	_drafts.clear()
	if _catalog != null:
		for event in _catalog.events:
			_entries.append(event)
	_selected_index = -1
	_draft = null
	if is_node_ready():
		_refresh_list()
		if not _entries.is_empty():
			_select_index(0)
		else:
			_refresh_form()

func select_event(id: StringName) -> void:
	for index in _entries.size():
		if _effective_entry(index).id == id:
			_select_index(index)
			return
	if is_node_ready():
		%Status.text = "未找到事件：" + str(id)

func draft() -> Resource:
	return _draft

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if _draft == null:
		errors.append("id: 请先选择或创建事件")
		return errors
	for message in _draft.validate():
		errors.append(message)
	if _catalog != null and _catalog.content_version >= 3 and _draft.mentor_comment.strip_edges().is_empty():
		errors.append("mentor_comment: 请填写67的一行评价")
	if not _safe_id(str(_draft.id)):
		errors.append("id: 文件标识只允许英文字母、数字、下划线和连字符")
	for index in _entries.size():
		if index != _selected_index and _effective_entry(index).id == _draft.id:
			errors.append("id: 事件 ID 已存在")
	if _catalog != null:
		if not _draft.external_preset_id.is_empty():
			var known_preset := false
			for preset in _catalog.presets:
				if preset != null and preset.id == _draft.external_preset_id: known_preset = true
			if not known_preset:
				errors.append("external_preset_id: 未登记的独立环境家族预设 " + str(_draft.external_preset_id))
		for topic in _draft.topic_ids:
			if not _catalog.topics.has(topic):
				errors.append("topic_ids: 未登记的主题 " + topic)
		for operation in _draft.operation_ids:
			if not operation in MemeDemoCatalog.OPERATION_IDS:
				errors.append("operation_ids: 未登记的操作 " + operation)
		var known_kernels := PackedStringArray()
		for kernel in _catalog.kernels:
			known_kernels.append(str(kernel.id))
		for discovery in _draft.discovery_ids:
			if not known_kernels.has(discovery):
				errors.append("discovery_ids: 未登记的基模 " + discovery)
		var known_groups := PackedStringArray()
		for group in _catalog.groups:
			known_groups.append(str(group.id))
		for index in _draft.effects.size():
			if _draft.effects[index] == null:
				continue
			for id in _draft.effects[index].group_ids:
				if not known_groups.has(id):
					errors.append("effects[%d].group_ids: 未登记的群体 %s" % [index, id])
	for index in _draft.design_rewards.size():
		var reward: Dictionary = _draft.design_rewards[index]
		var field: String = {"module":"modules","solute":"solutes","solvent":"solvents"}.get(str(reward.get("kind","")), "")
		if field.is_empty() or DESIGN_RULES.find(field,str(reward.get("id",""))).is_empty():
			errors.append("design_rewards[%d].id: 未登记的物品，不能保存或领取" % index)
	return errors

func save_selected() -> Error:
	_sync_draft()
	var errors := validation_errors()
	_show_errors(errors)
	if not errors.is_empty():
		%Status.text = "未保存：请点击错误定位；原文件未覆盖。"
		return ERR_INVALID_DATA
	if not _allowed_directory(edit_directory):
		_show_errors(PackedStringArray(["id: 保存目录必须是 res://content/demo/events"]))
		%Status.text = "未保存：不允许的目录。"
		return ERR_INVALID_PARAMETER
	var path := edit_directory.simplify_path().path_join(str(_draft.id) + ".tres")
	if FileAccess.file_exists(path) and _entries[_selected_index].resource_path != path:
		%Status.text = "未保存：同名文件已存在且不属于当前选中事件。"
		return ERR_ALREADY_EXISTS
	var error := _atomic_save(_draft, path)
	if error != OK:
		%Status.text = "保存失败（%s）：%s；原文件未覆盖。" % [error_string(error), path]
		return error
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as MemeDemoEvent
	if loaded == null:
		%Status.text = "文件已写入但重新加载失败：" + path
		return ERR_FILE_CORRUPT
	var previous: MemeDemoEvent = _entries[_selected_index]
	_entries[_selected_index] = loaded
	if _catalog != null:
		var replaced := false
		for index in _catalog.events.size():
			if _catalog.events[index] == previous or _catalog.events[index].id == previous.id:
				_catalog.events[index] = loaded
				replaced = true
				break
		if not replaced:
			_catalog.events.append(loaded)
	_draft = _clone_event(loaded)
	_drafts[_selected_index] = _draft
	_refresh_list()
	_refresh_form()
	%Status.text = "已保存并重新加载：" + path + "（编辑 catalog 仅更新内存）"
	return OK

func save_catalog(path: String = "res://content/demo/catalog.edited.tres") -> Error:
	if _catalog == null:
		return ERR_UNCONFIGURED
	path = path.simplify_path()
	if path != "res://content/demo/catalog.edited.tres":
		return ERR_INVALID_PARAMETER
	var errors: PackedStringArray = _catalog.validate()
	if not errors.is_empty():
		_show_errors(errors)
		%Status.text = "开发 catalog 未保存：内容验证失败。"
		return ERR_INVALID_DATA
	var error := _atomic_save(_catalog, path)
	%Status.text = "开发 catalog 已保存：" + path + "；不会改变当前运行，下一局请显式加载。" if error == OK else "开发 catalog 保存失败：" + error_string(error)
	return error

func reload_selected() -> void:
	if _selected_index < 0:
		return
	var source := _entries[_selected_index]
	if not source.resource_path.is_empty():
		var loaded := ResourceLoader.load(source.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as MemeDemoEvent
		if loaded == null:
			%Status.text = "重新加载失败；保留当前草稿：" + source.resource_path
			return
		_entries[_selected_index] = loaded
	_draft = _clone_event(_entries[_selected_index])
	_drafts[_selected_index] = _draft
	_condition_index = -1
	_effect_index = -1
	_refresh_form()
	%Status.text = "已重新加载选中事件；未保存的编辑已丢弃。"

func create_event() -> void:
	var event := MemeDemoEvent.new()
	event.id = _unique_id("event_new")
	event.title = "新事件"
	event.narrative = "填写消息的主体、发生的变化与后果。"
	event.mentor_comment = "先查清消息，再决定你要对谁说什么。"
	event.operation_ids = PackedStringArray(["attention_shift"])
	if _catalog != null and not _catalog.topics.is_empty():
		event.topic_ids = PackedStringArray([_catalog.topics[0]])
	event.effects.append(MemeDemoEffect.new())
	_entries.append(event)
	_select_index(_entries.size() - 1)
	%Status.text = "新事件是未保存草稿。"

func duplicate_selected() -> void:
	if _draft == null:
		return
	_sync_draft()
	var event := _clone_event(_draft)
	event.id = _unique_id(str(_draft.id) + "_copy")
	event.title += "（副本）"
	_entries.append(event)
	_select_index(_entries.size() - 1)
	%Status.text = "已复制为未保存草稿；原事件不变。"

func add_condition() -> void:
	if _draft == null: return
	_sync_draft()
	_draft.conditions.append(MemeDemoCondition.new())
	_condition_index = _draft.conditions.size() - 1
	_refresh_condition_list()
	_refresh_condition_form()
	_refresh_preview()

func remove_condition() -> void:
	if _draft == null or _condition_index < 0: return
	_sync_draft()
	_draft.conditions.remove_at(_condition_index)
	_condition_index = mini(_condition_index, _draft.conditions.size() - 1)
	_refresh_condition_list()
	_refresh_condition_form()
	_refresh_preview()

func add_effect() -> void:
	if _draft == null: return
	_sync_draft()
	_draft.effects.append(MemeDemoEffect.new())
	_effect_index = _draft.effects.size() - 1
	_refresh_effect_list()
	_refresh_effect_form()
	_refresh_preview()

func remove_effect() -> void:
	if _draft == null or _effect_index < 0: return
	_sync_draft()
	_draft.effects.remove_at(_effect_index)
	_effect_index = mini(_effect_index, _draft.effects.size() - 1)
	_refresh_effect_list()
	_refresh_effect_form()
	_refresh_preview()

func _select_index(index: int) -> void:
	if _draft != null and _selected_index >= 0:
		_drafts[_selected_index] = _draft
	_selected_index = index
	_draft = _drafts[index] if _drafts.has(index) else _clone_event(_entries[index])
	_condition_index = 0 if not _draft.conditions.is_empty() else -1
	_effect_index = 0 if not _draft.effects.is_empty() else -1
	if is_node_ready():
		_refresh_list()
		_refresh_form()

func _on_event_selected(index: int) -> void:
	_select_index(int(%EventList.get_item_metadata(index)))

func _refresh_list() -> void:
	if not is_node_ready(): return
	%EventList.clear()
	var query: String = %Search.text.strip_edges().to_lower()
	for index in _entries.size():
		var event := _effective_entry(index)
		var label := str(event.id) + " · " + event.title
		if not query.is_empty() and not label.to_lower().contains(query): continue
		var row: int = %EventList.add_item(label)
		%EventList.set_item_metadata(row, index)
		if index == _selected_index: %EventList.select(row)
	%Duplicate.disabled = _draft == null

func _refresh_form() -> void:
	if not is_node_ready(): return
	%Tabs.visible = _draft != null
	%Save.disabled = _draft == null
	%Reload.disabled = _draft == null
	if _draft == null:
		%ActionPreview.text = "选择事件后查看实际作用。"
		_show_errors(PackedStringArray())
		return
	_loading = true
	%EventId.text = str(_draft.id)
	%EventTitle.text = _draft.title
	%Narrative.text = _draft.narrative
	%MentorComment.text = _draft.mentor_comment
	_select_option(%Origin, str(_draft.origin))
	%Topics.text = ", ".join(_draft.topic_ids)
	%Operations.text = ", ".join(_draft.operation_ids)
	%ExternalPreset.text = str(_draft.external_preset_id)
	%Discoveries.text = ", ".join(_draft.discovery_ids)
	%EvidenceStatus.text = str(_draft.evidence_status)
	%ContentReference.text = "主题：" + ", ".join(_catalog.topics) + "\n操作：" + ", ".join(MemeDemoCatalog.OPERATION_IDS) if _catalog != null else "未配置内容字典。"
	_select_option(%TriggerMode, str(_draft.trigger_mode))
	%StartHour.value = _draft.start_hour
	%Weight.value = _draft.weight
	%Chance.value = _draft.occurrence_chance
	%Cooldown.value = _draft.cooldown_hours
	%MaxOccurrences.value = _draft.max_occurrences
	%PhysicalDuration.value = _draft.physical_duration_hours
	%AttentionDuration.value = _draft.attention_duration_hours
	_select_option(%DecayModel, str(_draft.attention_decay))
	%DecayParameter.value = _draft.decay_parameter_hours
	var group_labels := PackedStringArray()
	if _catalog != null:
		for group in _catalog.groups: group_labels.append(str(group.id) + "=" + group.title)
	%GroupReference.text = "群体参考（空列表=全部）：" + "；".join(group_labels)
	_loading = false
	_reward_index = -1
	_refresh_rewards()
	_refresh_condition_list()
	_refresh_effect_list()
	_refresh_condition_form()
	_refresh_effect_form()
	_refresh_preview()

func _sync_draft() -> void:
	if _loading or _draft == null or not is_node_ready(): return
	_draft.id = StringName(%EventId.text.strip_edges())
	_draft.title = %EventTitle.text
	_draft.narrative = %Narrative.text
	_draft.mentor_comment = %MentorComment.text
	_draft.origin = StringName(%Origin.get_item_text(%Origin.selected))
	_draft.topic_ids = _ids(%Topics.text)
	_draft.operation_ids = _ids(%Operations.text)
	_draft.external_preset_id = StringName(%ExternalPreset.text.strip_edges())
	_draft.discovery_ids = _ids(%Discoveries.text)
	_draft.evidence_status = StringName(%EvidenceStatus.text.strip_edges())
	_draft.trigger_mode = StringName(%TriggerMode.get_item_text(%TriggerMode.selected))
	_draft.start_hour = %StartHour.value
	_draft.weight = %Weight.value
	_draft.occurrence_chance = %Chance.value
	_draft.cooldown_hours = %Cooldown.value
	_draft.max_occurrences = int(%MaxOccurrences.value)
	_draft.physical_duration_hours = %PhysicalDuration.value
	_draft.attention_duration_hours = %AttentionDuration.value
	_draft.attention_decay = StringName(%DecayModel.get_item_text(%DecayModel.selected))
	_draft.decay_parameter_hours = %DecayParameter.value
	if _condition_index >= 0 and _condition_index < _draft.conditions.size():
		var condition: MemeDemoCondition = _draft.conditions[_condition_index]
		condition.field = StringName(%ConditionField.get_item_text(%ConditionField.selected))
		condition.operator = StringName(%ConditionOperator.get_item_text(%ConditionOperator.selected))
		condition.value = %ConditionValue.value
	if _effect_index >= 0 and _effect_index < _draft.effects.size():
		var effect: MemeDemoEffect = _draft.effects[_effect_index]
		effect.effect_id = StringName(%EffectId.get_item_text(%EffectId.selected))
		effect.amount = %EffectAmount.value
		effect.duration_hours = %EffectDuration.value
		effect.group_ids = _ids(%EffectGroups.text)
	_refresh_condition_list()
	_refresh_effect_list()
	_refresh_list()
	_refresh_preview()

func _refresh_condition_list() -> void:
	%Conditions.clear()
	if _draft == null: return
	for condition in _draft.conditions:
		%Conditions.add_item("%s %s %s" % [condition.field, condition.operator, condition.value])
	if _condition_index >= 0: %Conditions.select(_condition_index)
	%RemoveCondition.disabled = _condition_index < 0

func _refresh_effect_list() -> void:
	%Effects.clear()
	if _draft == null: return
	for effect in _draft.effects:
		%Effects.add_item(effect.describe() if effect != null else "空效果（验证失败）")
	if _effect_index >= 0: %Effects.select(_effect_index)
	%RemoveEffect.disabled = _effect_index < 0

func _on_condition_selected(index: int) -> void:
	_sync_draft()
	_condition_index = index
	_refresh_condition_list()
	_refresh_condition_form()

func _on_effect_selected(index: int) -> void:
	_sync_draft()
	_effect_index = index
	_refresh_effect_list()
	_refresh_effect_form()

func _refresh_condition_form() -> void:
	%ConditionForm.visible = _condition_index >= 0
	if _condition_index < 0: return
	_loading = true
	var condition: MemeDemoCondition = _draft.conditions[_condition_index]
	_select_option(%ConditionField, str(condition.field))
	_select_option(%ConditionOperator, str(condition.operator))
	%ConditionValue.value = condition.value
	_loading = false

func _refresh_effect_form() -> void:
	%EffectForm.visible = _effect_index >= 0
	if _effect_index < 0: return
	_loading = true
	var effect: MemeDemoEffect = _draft.effects[_effect_index]
	_select_option(%EffectId, str(effect.effect_id))
	%EffectAmount.value = effect.amount
	%EffectDuration.value = effect.duration_hours
	%EffectGroups.text = ", ".join(effect.group_ids)
	_loading = false

func _refresh_preview() -> void:
	%ActionPreview.text = "实际作用（由 effects 派生，不能独立填写）：\n" + _draft.effect_summary()
	if not _draft.design_rewards.is_empty():
		%ActionPreview.text += "\n确认后物品：" + _draft.design_reward_summary()
	%NarrativePreview.text = "%s\n%s\n%s\n67：%s" % [_draft.title, _draft.narrative, _draft.impact_summary(), _draft.mentor_comment]
	_show_errors(validation_errors())

func _show_errors(errors: PackedStringArray) -> void:
	_last_errors = errors
	%Errors.clear()
	for message in errors: %Errors.add_item(message)
	%ErrorHeading.text = "验证通过" if errors.is_empty() else "验证错误（点击定位）· %d" % errors.size()

func _focus_error(index: int) -> void:
	if index < 0 or index >= _last_errors.size(): return
	var message := _last_errors[index]
	if message.begins_with("design_rewards") or message.contains("design paper reward"):
		%Tabs.current_tab = _reward_tab.get_index()
		_reward_item.grab_focus()
		return
	var indexed := RegEx.new()
	indexed.compile("(conditions|effects)\\[(\\d+)\\]")
	var match_result := indexed.search(message)
	if match_result != null:
		var item_index := int(match_result.get_string(2))
		if match_result.get_string(1) == "conditions" and item_index < _draft.conditions.size():
			%Tabs.current_tab = 2
			_on_condition_selected(item_index)
			%Conditions.select(item_index)
			var control_name := "ConditionValue"
			if message.contains(".field"): control_name = "ConditionField"
			elif message.contains(".operator"): control_name = "ConditionOperator"
			_focus_control(control_name)
		elif item_index < _draft.effects.size():
			%Tabs.current_tab = 3
			_on_effect_selected(item_index)
			%Effects.select(item_index)
			var control_name := "EffectAmount"
			if message.contains(".effect_id"): control_name = "EffectId"
			elif message.contains(".group_ids"): control_name = "EffectGroups"
			elif message.contains(".duration_hours"): control_name = "EffectDuration"
			_focus_control(control_name)
		return
	var mapping := {
		"id": [0, "EventId"], "title": [0, "EventTitle"], "origin": [0, "Origin"],
		"topic_ids": [0, "Topics"], "operation_ids": [0, "Operations"],
		"external_preset_id": [0, "ExternalPreset"],
		"trigger_mode": [1, "TriggerMode"], "start_hour": [1, "StartHour"], "weight": [1, "Weight"],
		"occurrence_chance": [1, "Chance"], "cooldown_hours": [1, "Cooldown"], "max_occurrences": [1, "MaxOccurrences"],
		"physical_duration_hours": [1, "PhysicalDuration"], "attention_duration_hours": [1, "AttentionDuration"],
		"attention_decay": [1, "DecayModel"], "decay_parameter_hours": [1, "DecayParameter"],
		"narrative": [4, "Narrative"], "mentor_comment": [4, "MentorComment"], "discovery_ids": [5, "Discoveries"], "evidence_status": [5, "EvidenceStatus"]}
	for field: String in mapping:
		if message.begins_with(field + ":") or message.begins_with(field + " "):
			%Tabs.current_tab = mapping[field][0]
			_focus_control(str(mapping[field][1]))
			return
	var normalized := message.to_lower().replace(" ", "_")
	var aliases := {"occurrence_chance": "occurrence_chance", "max_occurrences": "max_occurrences", "trigger_mode": "trigger", "attention_decay": "decay", "evidence_status": "evidence", "topic_ids": "topic", "operation_ids": "operation", "discovery_ids": "discovery", "origin": "origin", "cooldown_hours": "cooldown", "title": "title", "narrative": "narrative"}
	for field: String in aliases:
		if normalized.contains(str(aliases[field])):
			%Tabs.current_tab = mapping[field][0]
			_focus_control(str(mapping[field][1]))
			return

func _focus_control(name: String) -> void:
	var control: Control = get_node("%" + name)
	if control is SpinBox: control.get_line_edit().grab_focus()
	else: control.grab_focus()

func _effective_entry(index: int) -> MemeDemoEvent:
	if index == _selected_index and _draft != null: return _draft
	return _drafts[index] if _drafts.has(index) else _entries[index]

func _fill_options(control: OptionButton, values: Array) -> void:
	for value in values: control.add_item(value)

func _select_option(control: OptionButton, value: String) -> void:
	for index in control.item_count:
		if control.get_item_text(index) == value:
			control.select(index)
			return
	# Keep invalid imported values visible for validation instead of coercing them.
	control.add_item(value)
	control.select(control.item_count - 1)

func _ids(text: String) -> PackedStringArray:
	var result := PackedStringArray()
	for token in text.replace("，", ",").split(",", false):
		var id := token.strip_edges()
		if not id.is_empty(): result.append(id)
	return result

func _clone_event(source: MemeDemoEvent) -> MemeDemoEvent:
	var copy := source.duplicate(false) as MemeDemoEvent
	copy.design_rewards = source.design_rewards.duplicate(true)
	copy.conditions = []
	copy.effects = []
	# Resource.duplicate(true) does not isolate resources nested in these arrays.
	for condition in source.conditions:
		copy.conditions.append(condition.duplicate(false) as MemeDemoCondition if condition != null else null)
	for effect in source.effects:
		copy.effects.append(effect.duplicate(false) as MemeDemoEffect if effect != null else null)
	return copy

func _build_reward_editor() -> void:
	_reward_tab = VBoxContainer.new()
	_reward_tab.name = "奖励物品"
	%Tabs.add_child(_reward_tab)
	var note := Label.new()
	note.text = "物品来自已确认的事件实例；重复阅读不会重复发放。\n溶质需研磨培养，溶剂为不可逆消耗后的补给。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward_tab.add_child(note)
	_rewards = ItemList.new()
	_rewards.name = "DesignRewards"
	_rewards.custom_minimum_size.y = 150
	_rewards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reward_tab.add_child(_rewards)
	_rewards.item_selected.connect(_select_reward)
	var row := HBoxContainer.new()
	row.name = "RewardForm"
	_reward_tab.add_child(row)
	_reward_kind = OptionButton.new()
	_reward_kind.name = "RewardKind"
	for index in REWARD_KINDS.size():
		_reward_kind.add_item(["神经模块","溶质纸块","溶剂补给"][index])
		_reward_kind.set_item_metadata(index,REWARD_KINDS[index])
	row.add_child(_reward_kind)
	_reward_kind.item_selected.connect(func(_index: int) -> void:
		if _reward_loading: return
		_fill_reward_items()
		_reward_changed())
	_reward_item = OptionButton.new()
	_reward_item.name = "RewardItem"
	_reward_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_reward_item)
	_reward_item.item_selected.connect(func(_index: int) -> void: _reward_changed())
	_reward_count = SpinBox.new()
	_reward_count.name = "RewardCount"
	_reward_count.min_value = 1
	_reward_count.max_value = 64
	_reward_count.step = 1
	row.add_child(_reward_count)
	_reward_count.value_changed.connect(func(_value: float) -> void: _reward_changed())
	var actions := HBoxContainer.new()
	actions.name = "RewardActions"
	_reward_tab.add_child(actions)
	var add := Button.new()
	add.name = "AddReward"
	add.text = "添加物品"
	add.pressed.connect(add_design_reward)
	actions.add_child(add)
	_reward_remove = Button.new()
	_reward_remove.name = "RemoveReward"
	_reward_remove.text = "删除所选"
	_reward_remove.pressed.connect(remove_design_reward)
	actions.add_child(_reward_remove)
	_fill_reward_items()
	_refresh_rewards()

func _fill_reward_items(selected_id: String = "") -> void:
	_reward_item.clear()
	var field: String = {"module":"modules","solute":"solutes","solvent":"solvents"}[REWARD_KINDS[_reward_kind.selected]]
	var entries: Array = DESIGN_RULES.get(field)
	for entry: Dictionary in entries:
		_reward_item.add_item(str(entry.get("title",entry.id)))
		_reward_item.set_item_metadata(_reward_item.item_count-1,str(entry.id))
		if str(entry.id) == selected_id: _reward_item.select(_reward_item.item_count-1)
	if not selected_id.is_empty() and DESIGN_RULES.find(field,selected_id).is_empty():
		_reward_item.add_item("未登记：" + selected_id)
		_reward_item.set_item_metadata(_reward_item.item_count-1,selected_id)
		_reward_item.select(_reward_item.item_count-1)

func add_design_reward() -> void:
	if _draft == null or _reward_item.selected < 0: return
	_draft.design_rewards.append({"kind":REWARD_KINDS[_reward_kind.selected],
		"id":str(_reward_item.get_item_metadata(_reward_item.selected)),"count":int(_reward_count.value)})
	_reward_index = _draft.design_rewards.size()-1
	_refresh_rewards()
	_refresh_preview()

func remove_design_reward() -> void:
	if _draft == null or _reward_index < 0: return
	_draft.design_rewards.remove_at(_reward_index)
	_reward_index = mini(_reward_index,_draft.design_rewards.size()-1)
	_refresh_rewards()
	_refresh_preview()

func _select_reward(index: int) -> void:
	if _draft == null or index < 0 or index >= _draft.design_rewards.size(): return
	_reward_index = index
	_reward_loading = true
	var reward: Dictionary = _draft.design_rewards[index]
	var kind_index := REWARD_KINDS.find(str(reward.get("kind","")))
	_reward_kind.select(maxi(kind_index,0))
	_fill_reward_items(str(reward.get("id","")))
	_reward_count.value = int(reward.get("count",1))
	_reward_loading = false
	_reward_remove.disabled = false

func _reward_changed() -> void:
	if _reward_loading or _draft == null or _reward_index < 0 or _reward_item.selected < 0: return
	_draft.design_rewards[_reward_index] = {"kind":REWARD_KINDS[_reward_kind.selected],
		"id":str(_reward_item.get_item_metadata(_reward_item.selected)),"count":int(_reward_count.value)}
	_refresh_rewards()
	_refresh_preview()

func _refresh_rewards() -> void:
	if _rewards == null: return
	_rewards.clear()
	if _draft != null:
		for reward: Dictionary in _draft.design_rewards:
			var field: String = {"module":"modules","solute":"solutes","solvent":"solvents"}.get(str(reward.get("kind","")), "")
			var entry: Dictionary = DESIGN_RULES.find(field,str(reward.get("id","")))
			_rewards.add_item("%s ×%d" % [str(entry.get("title",reward.get("id",""))),int(reward.get("count",0))])
		if _reward_index >= 0: _rewards.select(_reward_index)
	_reward_remove.disabled = _draft == null or _reward_index < 0

func _safe_id(value: String) -> bool:
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_-]+$")
	return regex.search(value) != null

func _unique_id(base: String) -> StringName:
	var candidate := base
	var suffix := 1
	while _has_id(candidate):
		candidate = base + "_" + str(suffix)
		suffix += 1
	return StringName(candidate)

func _has_id(id: String) -> bool:
	for event in _entries:
		if str(event.id) == id: return true
	for event: MemeDemoEvent in _drafts.values():
		if str(event.id) == id: return true
	return FileAccess.file_exists(edit_directory.path_join(id + ".tres"))

func _allowed_directory(path: String) -> bool:
	var clean := path.simplify_path().trim_suffix("/")
	return clean == "res://content/demo/events"

func _atomic_save(resource: Resource, path: String) -> Error:
	var directory := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK: return error
	var temporary := directory.path_join(".event_editor_%d_%d.tres" % [OS.get_process_id(), Time.get_ticks_usec()])
	error = ResourceSaver.save(resource, temporary)
	if error != OK: return error
	var staged := ResourceLoader.load(temporary, "", ResourceLoader.CACHE_MODE_IGNORE)
	if staged == null or not staged.call("validate").is_empty():
		var cleanup := DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		if cleanup != OK: push_error("Invalid staged resource cleanup failed: " + error_string(cleanup))
		return ERR_FILE_CORRUPT
	# Rename is the commit point; a refused replace leaves the original untouched.
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if error != OK:
		var cleanup := DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		if cleanup != OK: push_error("Staged resource cleanup failed: " + error_string(cleanup))
	return error
