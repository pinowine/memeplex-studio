## 组织编辑、语境和传播工作纸；所有库存与设计操作都交给模拟层提交。
class_name DeskDesignWorkbench
extends Control

signal draft_changed(draft: Dictionary)
signal design_action_requested(action: String, params: Dictionary)
signal skill_purchase_requested(id: String)
signal material_tabletop_requested(kind: String, id: String)
signal sheet_requested(id: String)
signal context_resource_detached(record: Dictionary, global_point: Vector2)
signal context_layer_detached(record: Dictionary, global_point: Vector2)
signal module_slots_pressed(viewport_rect: Rect2)

const Sketch = preload("res://scripts/presentation/studio/design/desk_neural_sketch.gd")
const DendriteTree = preload("res://scripts/presentation/studio/design/desk_dendrite_tree.gd")
const ContextSlice = preload("res://scripts/presentation/studio/context/desk_context_board.gd")
const ContextTrialSlip = preload("res://scripts/presentation/studio/context/desk_context_trial_slip.gd")
const ModuleClip = preload("res://scripts/presentation/studio/design/desk_module_paper_clip.gd")
const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const INK := Color("384238")
const TABS := ["edit", "cultivate", "spread"]
const ASSET_PATHS := {"modules": "res://assets/image/textures/studio/desk/neuron_family_bases.png"}
const MODULE_REGIONS := {
	"stance": Rect2(0, 0, 370, 724),
	"relation": Rect2(370, 0, 505, 724),
	"ritual": Rect2(875, 0, 440, 724),
	"boundary": Rect2(1315, 0, 425, 724),
	"shared_world": Rect2(1740, 0, 432, 724),
}

var _catalog: MemeDemoCatalog
const DEFAULT_RULES := preload("res://data/rules/design_rules.tres")
var _rules: MemeDesignRules = DEFAULT_RULES
var _draft: Dictionary = {}
var _state: Dictionary = {}
var _design: Dictionary = {}
var _tab := "edit"
var _selected_part := ""
var _selected_module := ""
var _selected_skill := "text"
var _selected_variant := ""
var _interaction_enabled := true
var _setting := false
var _pages: Dictionary = {}
var _tabs: Array[Button] = []
var _neuron: Control
var _starter: OptionButton
var _physical_clips: Array[Control] = []
var _part_title: Label
var _part_note: Label
var _part_content: RichTextLabel
var _final_expression: RichTextLabel
var _final_title: Label
var _detail_scroll: ScrollContainer
var _detail_stack: VBoxContainer
var _source: RichTextLabel
var _errors: Label
var _footer: Control
var _cost: Label
var _publish: Button
var _skill_buttons: Dictionary = {}
var _skill_title: Label
var _skill_details: RichTextLabel
var _buy: Button
var _apply_skill: Button
var _textures: Dictionary = {}
var _sync_count := 0
var _sheet_hosts: Dictionary = {}
var _spread_tree: Control
var _module_edits: Dictionary = {}
var _selected_installed_slot := -1
var _context_slice: Control
var _context_title: Label
var _context_details: RichTextLabel
var _context_trial: Control
var _overview_name: Label
var _overview_data: RichTextLabel
var _text_layout_queued := false
var _part_edit_identity := ""
var _catalog_default_slots: Dictionary = {}
var _catalog_default_modules: Dictionary = {}
var _catalog_default_name := ""
var _catalog_default_target := ""
var _edited_slots: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()
	resized.connect(_layout)
	select_tab("edit")
	_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_locale()

func _refresh_locale() -> void:
	if _part_content == null: return
	DeskLocalization.refresh_edits(self)
	_refresh_starters()
	_refresh_culture()
	_refresh_skills()
	_refresh_neuron()
	_refresh_part()
	_refresh_overview()
	if _neuron != null: _neuron.queue_redraw()
	if _spread_tree != null: _spread_tree.queue_redraw()
	_queue_text_layout()

func mark_catalog_defaults(preset_id: String) -> void:
	if _catalog == null or str(_draft.get("preset_id","")) != preset_id: return
	var preset: MemeDemoPreset = _catalog.find_preset(preset_id)
	if preset == null: return
	_catalog_default_slots.clear()
	_edited_slots.clear()
	var keys := preset.required_slots
	var values := preset.default_values
	var slots: Dictionary = _draft.get("slots",{})
	for index in mini(keys.size(),values.size()):
		if str(slots.get(keys[index],"")) == values[index]:
			_catalog_default_slots[keys[index]] = values[index]
	var title := preset.title
	_catalog_default_name = title if str(_draft.get("name",_draft.get("title",""))) == title else ""
	_catalog_default_target = title if str(_draft.get("target","")) == title else ""
	if _context_slice != null: _context_slice.set_authored_target(_catalog_default_target)
	if _context_trial != null: _context_trial.set_authored_target(_catalog_default_target)
	_part_edit_identity = ""
	_refresh_neuron()
	_refresh_part()
	_refresh_overview()

func _authored_slot_default(id: String, value: String) -> bool:
	return not _edited_slots.has(id) and _catalog_default_slots.has(id) and str(_catalog_default_slots[id]) == value

func _bind_part_content(value: String, identity: String, authored_default: bool = false) -> void:
	_part_edit_identity = identity
	_part_content.text = DeskLocalization.text(value) if authored_default else value


func configure(catalog: MemeDemoCatalog, rules: MemeDesignRules = null) -> void:
	_catalog = catalog
	_rules = rules if rules != null else DEFAULT_RULES
	if _context_slice != null: _context_slice.configure(_rules)
	if _context_trial != null: _context_trial.configure(_catalog, _rules)
	_refresh_starters()
	_refresh_skills()
	load_assets()


func load_assets(textures: Dictionary = {}) -> void:
	for id in ["modules"]:
		if textures.has(id): _textures[id]=textures[id]
		elif ResourceLoader.exists(ASSET_PATHS[id]): _textures[id]=load(ASSET_PATHS[id]) as Texture2D
	_refresh_culture()
	_refresh_neuron()
	_layout()


func bind_publish(button: Button, cost: Label) -> void:
	_publish=button
	_cost=cost
	button.reparent(_footer)
	PaperStyle.apply_button(button)
	button.clip_text = false
	if not button.minimum_size_changed.is_connected(_queue_text_layout): button.minimum_size_changed.connect(_queue_text_layout)
	cost.hide()
	button.visible = int(_state.get("publish_count", 0)) > 0
	_layout()


func set_draft(draft: Dictionary) -> void:
	if _draft == draft: return
	if str(_draft.get("preset_id","")) != str(draft.get("preset_id","")) or str(_draft.get("kernel_id","")) != str(draft.get("kernel_id","")):
		_catalog_default_slots.clear()
		_edited_slots.clear()
		_catalog_default_name = ""
		_catalog_default_target = ""
		if _context_slice != null: _context_slice.set_authored_target("")
		if _context_trial != null: _context_trial.set_authored_target("")
	_draft=draft.duplicate(true)
	if _context_trial != null: _context_trial.set_draft(get_draft())
	_refresh_neuron()
	_refresh_part()
	_refresh_starters()
	_refresh_overview()


func get_draft() -> Dictionary:
	return _draft.duplicate(true)


func sync_state(snapshot: Dictionary) -> void:
	var design: Dictionary=snapshot.get("design_state",{})
	var relevant := {"design_state":design,"meme_points":snapshot.get("meme_points",0),"phase":snapshot.get("phase","draft"),"lineage":snapshot.get("lineage",[]),"publish_count":snapshot.get("publish_count",0)}
	if _state == relevant: return
	_state=relevant.duplicate(true)
	if _publish != null: _publish.visible = _tab == "edit" and int(_state.get("publish_count", 0)) > 0
	var previous_modules: Array = _design.get("module_slots", [])
	_design=design.duplicate(true)
	var slots: Array=_design.get("module_slots",[])
	for index in slots.size():
		if not str(slots[index]).is_empty() and (index >= previous_modules.size() or slots[index] != previous_modules[index]):
			_selected_module = str(slots[index])
			_selected_installed_slot = index
			_selected_variant = ""
	if _selected_installed_slot>=0 and (_selected_installed_slot>=slots.size() or str(slots[_selected_installed_slot]).is_empty()): _selected_installed_slot=-1
	_sync_count+=1
	_refresh_culture()
	_refresh_neuron()
	_refresh_skills()
	_refresh_part()
	_refresh_overview()


func select_tab(id: String) -> void:
	if id not in TABS: return
	set_active_sheet(id)
	if not _sheet_hosts.is_empty(): sheet_requested.emit(id)


func set_active_sheet(id: String) -> void:
	if id not in TABS: return
	_tab=id
	set_interaction_enabled(_interaction_enabled)
	for key in _pages:
		if not _sheet_hosts.has(key): _pages[key].visible=key==id
	if _publish!=null: _publish.visible=id=="edit" and int(_state.get("publish_count", 0)) > 0
	if _cost!=null: _cost.hide()
	_layout()


func sheet_pages() -> Dictionary:
	return _pages.duplicate()


func mount_sheet(id: String,host: Control) -> void:
	if not _pages.has(id) or host==null: return
	var page: Control=_pages[id]
	_sheet_hosts[id]=host
	page.reparent(host)
	page.show()
	page.position=Vector2.ZERO
	page.size=host.size
	if not host.resized.is_connected(_resize_sheet.bind(id)): host.resized.connect(_resize_sheet.bind(id))
	_resize_sheet(id)


func _resize_sheet(id: String) -> void:
	if not _sheet_hosts.has(id): return
	var page: Control=_pages[id]
	page.position=Vector2.ZERO
	page.size=(_sheet_hosts[id] as Control).size
	_layout_sheet(id,page.size)


func report_errors(errors: PackedStringArray) -> void:
	_errors.text="\n".join(errors) if not errors.is_empty() else ""
	_errors.hide()


func _build() -> void:
	for index in TABS.size():
		var button:=_button(self,[DeskLocalization.text("LOC_EDIT_05183656"),DeskLocalization.text("LOC_CULTIVATE_62025174"),DeskLocalization.text("LOC_SPREAD_1A2DA4D4")][index],"Tab"+TABS[index].capitalize())
		button.toggle_mode=true
		button.pressed.connect(select_tab.bind(TABS[index]))
		_tabs.append(button)
		button.hide()
		var page:=Control.new()
		page.name=TABS[index].capitalize()+"Page"
		page.mouse_filter=Control.MOUSE_FILTER_IGNORE
		add_child(page)
		_pages[TABS[index]]=page
	_footer=Control.new()
	_footer.name="PublishFooter"
	_footer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_pages.edit.add_child(_footer)
	_errors=_label(self,"","DesignErrors")
	_errors.add_theme_color_override("font_color",Color("a44635"))
	_errors.hide()
	_build_edit()
	_build_culture()
	_build_spread()
	PaperStyle.apply_buttons(_pages.edit)
	PaperStyle.apply_buttons(_pages.spread)
	_starter.hide()


func _build_edit() -> void:
	var page: Control=_pages.edit
	_neuron=Sketch.new()
	_neuron.name="NeuralSketch"
	page.add_child(_neuron)
	_neuron.part_selected.connect(_select_part)
	_neuron.module_drop_requested.connect(func(slot: int,id: String) -> void: _request("install_module",{"slot":slot,"module_id":id}))
	_neuron.connection_requested.connect(func(from: int,to: int) -> void: _request("connect",{"from":from,"to":to}))
	_neuron.installed_selected.connect(func(slot: int,id: String) -> void: show_module(id,slot))
	_neuron.variant_selected.connect(_select_variant)
	_neuron.module_position_changed.connect(func(slot: int,point: Vector2) -> void: _request("move_module",{"slot":slot,"position":point}))
	_starter=OptionButton.new()
	_starter.name="StarterConfiguration"
	_starter.disabled=true
	page.add_child(_starter)
	_starter.item_selected.connect(_choose_starter)
	for index in 5:
		var clip := ModuleClip.new()
		clip.name = "PaperClip%d" % index
		page.add_child(clip)
		_physical_clips.append(clip)
		clip.pressed.connect(func(): module_slots_pressed.emit(module_clips_viewport_rect()))
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "ExpressionDetails"
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_detail_scroll)
	_detail_stack = VBoxContainer.new()
	_detail_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_stack.add_theme_constant_override("separation", 10)
	_detail_scroll.add_child(_detail_stack)
	_overview_data = _readout(_detail_stack, "MemeOverviewData", 16)
	_overview_data.bbcode_enabled = true
	_part_title = _label(_detail_stack, "", "PartTitle", 19)
	_part_note = _label(_detail_stack, "", "PartDescription", 14)
	_part_content = _readout(_detail_stack, "PartContent", 16)
	_source = _readout(_detail_stack, "SourceAndMutation", 13)
	_overview_name = _label(page, "", "MemeOverviewName", 24)
	_overview_name.set_meta("paper_emphasis", true)
	_final_title = _label(page, DeskLocalization.source("LOC_EDIT_FINAL_EXPRESSION"), "FinalExpressionTitle", 14)
	_final_expression = _readout(page, "FinalExpression", 23)
	_final_expression.fit_content = false
	_final_expression.scroll_active = true


func _readout(parent: Node, node_name: String, font_size: int) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.name = node_name
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	label.add_theme_constant_override("line_separation", 6)
	label.add_theme_color_override("default_color", INK)
	parent.add_child(label)
	return label


func _build_culture() -> void:
	var page: Control = _pages.cultivate
	_context_slice = ContextSlice.new()
	_context_slice.name = "ContextSlice"
	page.add_child(_context_slice)
	_context_slice.set_action_callback(_request)
	_context_slice.selected_info_changed.connect(_show_context_info)
	_context_slice.resource_detached.connect(func(record: Dictionary,point: Vector2) -> void:
		material_tabletop_requested.emit(str(record.get("kind","")),str(record.get("id","")))
		context_resource_detached.emit(record,point))
	_context_slice.context_layer_detached.connect(func(record: Dictionary,point: Vector2): context_layer_detached.emit(record,point))
	_context_title = _label(page,DeskLocalization.source("LOC_CORTEX_LANGUAGE_0D41EBCC"),"ContextLayerTitle",20)
	_context_details = RichTextLabel.new()
	_context_details.name = "ContextLayerDetails"
	_context_details.add_theme_font_size_override("normal_font_size",14)
	_context_details.add_theme_color_override("default_color",INK)
	_context_details.selection_enabled = true
	_context_details.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(_context_details)
	_context_trial = ContextTrialSlip.new()
	_context_trial.name = "ContextTrialSlip"
	page.add_child(_context_trial)
	_context_trial.configure(_catalog, _rules)


func _build_spread() -> void:
	_spread_tree=DendriteTree.new()
	_spread_tree.name="DendriteTree"
	_pages.spread.add_child(_spread_tree)
	_spread_tree.node_selected.connect(_select_skill)
	var page: Control=_pages.spread
	_skill_title=_label(page,DeskLocalization.source("LOC_TEXT_DD818618"),"SkillTitle",18)
	_skill_details=RichTextLabel.new()
	_skill_details.name="SkillDetails"
	_skill_details.bbcode_enabled=false
	_skill_details.add_theme_color_override("default_color",INK)
	_skill_details.add_theme_font_size_override("normal_font_size",14)
	page.add_child(_skill_details)
	_buy=_button(page,DeskLocalization.source("LOC_RESEARCH_THIS_NODE_9222A1F7"),"BuySkill")
	_buy.pressed.connect(func() -> void: skill_purchase_requested.emit(_selected_skill))
	_apply_skill=_button(page,DeskLocalization.source("LOC_APPLY_ABILITY_TO_DRAFT_DD49D83A"),"ApplySkill")
	_apply_skill.pressed.connect(func() -> void: _request("apply_skill",{"skill_id":_selected_skill}))


func _refresh_starters() -> void:
	if _starter == null or _catalog == null: return
	var chosen:=str(_draft.get("preset_id",""))
	var ids:=_rules.starter_presets
	_starter.clear()
	for preset in _catalog.presets:
		var id:=str(preset.id)
		if id not in ids and id!=chosen: continue
		_starter.add_item(DeskLocalization.text(preset.title))
		_starter.set_item_metadata(_starter.item_count-1,id)
		if id==chosen: _starter.select(_starter.item_count-1)


func _choose_starter(index: int) -> void:
	if index<0 or index>=_starter.item_count: return
	var id:=str(_starter.get_item_metadata(index))
	for preset in _catalog.presets:
		if str(preset.id)!=id: continue
		var changed := preset.to_draft(_draft)
		changed.target = preset.title
		set_draft(changed)
		mark_catalog_defaults(id)
		draft_changed.emit(get_draft())
		return


func _refresh_neuron() -> void:
	if _neuron==null: return
	var id:=str(_draft.get("kernel_id",""))
	var module:=_module_for_kernel(id)
	var nodes: Array=module.get("neuron_nodes",[])
	var edges: Array=module.get("neuron_edges",[])
	if nodes.is_empty():
		for slot in (_draft.get("slots",{}) as Dictionary): nodes.append({"id":slot,"title":slot})
	var source_slots: Dictionary = _draft.get("slots",{})
	_neuron.configure(id,nodes,edges,source_slots)
	var displayed_slots := {}
	for key: String in source_slots:
		var value := str(source_slots[key])
		displayed_slots[key] = DeskLocalization.text(value) if _authored_slot_default(key,value) else value
	_neuron.set_display_slots(displayed_slots)
	_neuron.set_family_texture(_module_texture(id))
	_neuron.sync_design(_design.get("module_slots",[]),_design.get("connections",[]),_design.get("lineage_view",_state.get("lineage",[])))
	_neuron.set_module_positions(_design.get("module_positions",[]))
	var current_exists := false
	for node in nodes:
		if str(node.get("id",""))==_selected_part: current_exists=true
	if not current_exists and not nodes.is_empty(): _select_part(str(nodes[0].id))


func _select_part(id: String) -> void:
	_selected_part=id
	_selected_module=""
	_selected_variant=""
	_selected_installed_slot=-1
	_neuron.select_part(id)
	_refresh_part()


func _refresh_part() -> void:
	if _part_title==null: return
	if not _selected_variant.is_empty():
		_select_variant(_selected_variant)
		return
	if not _selected_module.is_empty():
		show_module(_selected_module,_selected_installed_slot)
		return
	_setting=true
	var definition:=_module_for_kernel(str(_draft.get("kernel_id","")))
	var title:=_selected_part
	for node in definition.get("neuron_nodes",[]):
		if str(node.get("id",""))==_selected_part: title=DeskLocalization.text(str(node.get("title",_selected_part)))
	_part_title.text=title
	_part_note.text=DeskLocalization.text("LOC_EDIT_READ_ONLY_PART")
	var content := str((_draft.get("slots",{}) as Dictionary).get(_selected_part,""))
	_bind_part_content(content,"slot:"+str(_draft.get("preset_id",""))+":"+_selected_part,_authored_slot_default(_selected_part,content))
	_source.text=""
	_setting=false


func show_module(id: String,slot: int=-1) -> void:
	_selected_installed_slot=slot
	_selected_module=id
	_selected_variant=""
	for entry in _rules.modules:
		if str(entry.id)!=id: continue
		_setting=true
		_part_title.text=DeskLocalization.text(str(entry.title))
		_part_note.text=DeskLocalization.text(str(entry.description))
		var content:=str(_module_edits.get(id,entry.get("content","")))
		if _selected_installed_slot>=0:
			var contents: Array=_design.get("module_contents",[])
			if _selected_installed_slot<contents.size(): content=str(contents[_selected_installed_slot])
		var from_definition: bool = not _module_edits.has(id) and content == str(entry.get("content","")) and (_selected_installed_slot < 0 or _catalog_default_modules.get(id) == content)
		_bind_part_content(content,"module:"+id+":"+str(_selected_installed_slot),from_definition)
		_source.text=""
		_setting=false
		return


func _select_variant(id: String) -> void:
	for variant in _design.get("lineage_view",[]):
		if str(variant.get("id",""))!=id: continue
		_selected_variant=id
		_selected_module=""
		_selected_installed_slot=-1
		_setting=true
		_part_title.text=DeskLocalization.text("LOC_CIRCULATING_EXPRESSION_48990024")
		_part_note.text=DeskLocalization.text("LOC_YOUR_OWN_EXPRESSION_0A35E8E2") if bool(variant.get("controlled",false)) else DeskLocalization.text("LOC_SOMEONE_ELSE_S_REWRITE_90C4EF5E")
		_bind_part_content(str(variant.get("text","")),"variant:"+id,false)
		_source.text=DeskLocalization.text("LOC_REWRITTEN_FROM_AN_EARLIER_EXPRESSION_22EA25D8") if not (variant.get("parent_ids",[]) as Array).is_empty() else DeskLocalization.text("LOC_AN_INDEPENDENTLY_EMERGING_EXPRESSION_77A66F57")
		_setting=false
		return


func _refresh_culture() -> void:
	if _context_slice == null: return
	_context_slice.set_state(_design)
	_show_context_info(_context_slice.selected_info())


func _request(action: String, params: Dictionary) -> void:
	var request:=params.duplicate(true)
	if action in ["install_module","remove_module","edit_module_content","install_context","remove_context","move_context_axis","detach_context_layer","attach_context_layer"]:
		request["draft"]=get_draft()
		if action=="install_module":
			var module_id := str(request.get("module_id",""))
			request["content"]=str(_module_edits.get(module_id,_module_content(module_id)))
			if not _module_edits.has(module_id) and request.content == _module_content(module_id):
				_catalog_default_modules[module_id] = request.content
	design_action_requested.emit(action,request)


func _refresh_skills() -> void:
	if _skill_details==null: return
	var skills:=_rules.skills
	for skill in skills:
		var id:=str(skill.id)
		if not _skill_buttons.has(id):
			var button:=_button(_pages.spread,str(skill.title),"Skill"+id.capitalize())
			button.pressed.connect(_select_skill.bind(id))
			_skill_buttons[id]=button
		var unlocked: bool=id in _design.get("unlocked_skills",["text"])
		(_skill_buttons[id] as Button).text=("● " if unlocked else "○ ")+DeskLocalization.text(str(skill.title))
	_spread_tree.configure(_rules.skills.duplicate(true))
	_spread_tree.sync_state(_design.get("unlocked_skills",["text"]),_selected_skill)
	_select_skill(_selected_skill)
	_layout()


func _select_skill(id: String) -> void:
	_selected_skill=id
	if _spread_tree!=null: _spread_tree.sync_state(_design.get("unlocked_skills",["text"]),id)
	for skill in _rules.skills:
		if str(skill.id)!=id: continue
		var unlocked: bool=id in _design.get("unlocked_skills",["text"])
		var missing: Array=[]
		for dependency in skill.get("requires",[]):
			if str(dependency) not in _design.get("unlocked_skills",["text"]): missing.append(dependency)
		_skill_title.text=DeskLocalization.text(str(skill.title))
		var dependency_titles:=PackedStringArray()
		for dependency in skill.get("requires",[]): dependency_titles.append(_entry_title("skills",str(dependency)))
		_skill_details.text=DeskLocalization.format_text("LOC_S_EFFECT_S_REQUIRES_S_COST_D_35DC10A9", [DeskLocalization.text(str(skill.get("description",""))),DeskLocalization.text(str(skill.get("effect_text",skill.get("effect",skill.get("description",""))))),", ".join(dependency_titles) if not dependency_titles.is_empty() else DeskLocalization.text("LOC_NONE_484D5561"),int(skill.get("cost",0)),int(_state.get("meme_points",0)),DeskLocalization.text("LOC_UNLOCKED_E4CF2DE9") if unlocked else (DeskLocalization.text("LOC_REQUIREMENTS_NOT_MET_114C5744") if not missing.is_empty() else DeskLocalization.text("LOC_AVAILABLE_TO_UNLOCK_097705A8"))])
		_buy.disabled=unlocked or not missing.is_empty() or int(_state.get("meme_points",0))<int(skill.get("cost",0))
		_buy.text=DeskLocalization.text("LOC_UNLOCKED_E4CF2DE9") if unlocked else DeskLocalization.format_text("LOC_SPEND_D_MEME_UNLOCK_45B2FF07", int(skill.get("cost",0)))
		var applied:=false
		for application in _design.get("skill_applications",[]):
			if str(application.get("skill_id",""))==id and int(application.get("publish_index",-1))==int(_design.get("current_publish_index",0)): applied=true
		_apply_skill.disabled=not unlocked or (skill.get("draft_effects",[]) as Array).is_empty() or applied
		_apply_skill.text=""
	_apply_skill.hide()


func _layout() -> void:
	if _pages.is_empty(): return
	for id in _pages:
		var page: Control=_pages[id]
		if _sheet_hosts.has(id):
			_resize_sheet(id)
		else:
			_place(page,Rect2(Vector2.ZERO,size))
			_layout_sheet(id,size)
	_place(_errors,Rect2(8,0,maxf(240,size.x-16),30))
	for button in _tabs: button.hide()
	_starter.hide()
	if _cost!=null: _cost.hide()
	queue_redraw()


func _layout_sheet(id: String,area: Vector2) -> void:
	var w:=maxf(area.x,360)
	var h:=maxf(area.y,280)
	if id=="edit": _layout_edit_sheet(w,h)
	elif id=="cultivate": _layout_culture_sheet(w,h)
	else: _layout_spread_sheet(w,h)


func _layout_edit_sheet(w: float, h: float) -> void:
	var right := w * .52
	var span := w - right - 8
	# Keep the title below the clips and clear of the physical monitor.
	_place(_overview_name, Rect2(right, 148, span, 38))
	var graph_y := 54.0
	var expression_y := maxf(graph_y + 110, h - 154)
	_place(_neuron, Rect2(0, graph_y, right - 18, maxf(100, expression_y - graph_y - 14)))
	_place(_final_title, Rect2(8, expression_y, right - 24, 24))
	_place(_final_expression, Rect2(8, expression_y + 30, right - 28, maxf(60, h - expression_y - 78)))
	for index in _physical_clips.size():
		var x := right + float(index) * (span - 96) / 4.0
		_place(_physical_clips[index], Rect2(x, 6, 96, 128))
		_physical_clips[index].rotation = deg_to_rad([-5.0, 3.5, -2.0, 5.5, -3.5][index])
	var details_y := _overview_name.position.y + _overview_name.size.y + 12
	_place(_detail_scroll, Rect2(right, details_y, span, maxf(78, h - 52 - details_y)))
	_place(_footer, Rect2(0, h - 44, w, 40))
	if _publish != null:
		var key_width := maxf(238, _publish.get_combined_minimum_size().x)
		_place(_publish, Rect2(w - key_width - 8, 4, key_width, maxf(32, _publish.get_combined_minimum_size().y)))


func _layout_culture_sheet(w: float,h: float) -> void:
	_context_title.hide()
	_place(_context_slice,Rect2(0,0,w,maxf(240,h)))
	_place(_context_details,Rect2())
	_place(_context_trial,Rect2())
	_context_details.hide()
	_context_trial.hide()

func _layout_spread_sheet(w: float,h: float) -> void:
	var right:=w*.61
	_place(_spread_tree,Rect2(0,0,right-16,h))
	_place(_skill_title,Rect2(right,18,w-right,29))
	var details_y := maxf(61, _skill_title.position.y + _skill_title.size.y + 14)
	_place(_skill_details,Rect2(right,details_y,w-right,maxf(72,h-74-details_y)))
	_place(_buy,Rect2(right,h-59,w-right,35))
	_apply_skill.hide()
	for button in _skill_buttons.values(): button.hide()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_neuron.set_interaction_enabled(enabled and _tab == "edit")
	for clip: Control in _physical_clips: clip.set_interaction_enabled(enabled and _tab == "edit")
	_spread_tree.set_interaction_enabled(enabled and _tab == "spread")
	if _context_slice != null: _context_slice.set_interaction_enabled(enabled and _tab == "cultivate")


func _button(parent: Node,text: String,name: String) -> Button:
	var node:=Button.new()
	node.name=name
	node.text=text
	node.clip_text=false
	node.add_theme_font_size_override("font_size",12)
	parent.add_child(node)
	PaperStyle.apply_button(node)
	node.minimum_size_changed.connect(_queue_text_layout)
	return node


func _label(parent: Node,text: String,name: String,font_size: int=12) -> Label:
	var node:=Label.new()
	node.name=name
	node.text=text
	node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",INK)
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	node.minimum_size_changed.connect(_queue_text_layout)
	return node


func _queue_text_layout() -> void:
	if _text_layout_queued: return
	_text_layout_queued = true
	call_deferred("_flush_text_layout")


func _flush_text_layout() -> void:
	_text_layout_queued = false
	if is_inside_tree(): _layout()


func _place(node: Control,rect: Rect2) -> void:
	node.position=rect.position
	node.size=rect.size


func _kernel(id: String) -> MemeDemoKernel:
	if _catalog != null:
		for kernel: MemeDemoKernel in _catalog.kernels:
			if str(kernel.id) == id:
				return kernel
	return null

func _module_for_kernel(id: String) -> Dictionary:
	for module in _rules.modules:
		if str(module.get("kernel_id",""))==id: return module
	return {}


func _module_texture(id: String) -> Texture2D:
	if not _textures.has("modules") or not MODULE_REGIONS.has(id): return null
	var texture:=AtlasTexture.new()
	texture.atlas=_textures.modules
	texture.region=MODULE_REGIONS[id]
	return texture


func _entry_title(kind: String, id: String) -> String:
	if id.is_empty():
		return DeskLocalization.text("LOC_NOT_SELECTED_1182C545")
	var entry := _rules.find(kind, id)
	return DeskLocalization.text(str(entry.get("title", id)))

func inspection() -> Dictionary:
	return {"tab":_tab,"tabs":TABS,"draft":get_draft(),"neuron":_neuron.inspection(),"design_state":_design.duplicate(true),"sync_count":_sync_count,
		"module_slots":_physical_clips.size(),"skill_count":_skill_buttons.size(),
		"selected_part":_selected_part,"selected_skill":_selected_skill,"selected_module":_selected_module,"selected_variant":_selected_variant,
		"content_editable":false,"final_expression":_final_expression.text,"final_expression_rect":_final_expression.get_global_rect(),"source_text":_source.text,"skill_details":_skill_details.text,"buy_disabled":_buy.disabled,"error_text":_errors.text,
		"footer_rect":_footer.get_global_rect(),"part_rect":_part_content.get_global_rect(),"neuron_rect":_neuron.get_global_rect(),
		"starter_options":_starter.item_count,"publication_connected":_publish!=null,"inventory_sources":_design.get("inventory_sources",[]).duplicate(true),
		"context_slice":_context_slice.inspection(),"context_trial":context_trial_inspection(),"culture_instruction_visible":_context_details.is_visible_in_tree(),
		"overview":{"name":_overview_name.text,"data":_overview_data.text,"name_rect":_overview_name.get_global_rect(),"data_rect":_overview_data.get_global_rect()},
		"spread_tree":_spread_tree.inspection(),"module_slot_rects":_physical_clips.map(func(clip: Control)->Rect2:return clip.get_global_rect()),
		"sheet_pages":_pages.keys(),"state_mutation":"signals only; authoritative simulation applies resources"}


func module_clip_parent(slot: int) -> Control:
	return _physical_clips[slot] if slot>=0 and slot<_physical_clips.size() else null


func module_clip_at(point: Vector2, empty_only: bool = false) -> int:
	var best := -1
	var distance := INF
	var slots: Array = _design.get("module_slots", [])
	for slot in _physical_clips.size():
		if empty_only and (slot >= slots.size() or not str(slots[slot]).is_empty()): continue
		var clip: Control = _physical_clips[slot]
		if not clip.accepts(point): continue
		var center: Vector2 = clip.get_global_transform_with_canvas() * (clip.size * .5)
		var candidate := center.distance_squared_to(point)
		if candidate < distance:
			distance = candidate
			best = slot
	return best


func module_clips_viewport_rect() -> Rect2:
	var rect := Rect2()
	for clip: Control in _physical_clips:
		var bounds: Rect2 = clip.get_global_transform_with_canvas() * Rect2(Vector2.ZERO,clip.size)
		rect = rect.merge(bounds) if rect.has_area() else bounds
	return rect


func accept_tabletop_item(kind: String,id: String,global_position: Vector2) -> bool:
	if not _interaction_enabled or not is_visible_in_tree() or id.is_empty(): return false
	if kind=="module" and _tab=="edit":
		var free:=int((_design.get("available_module_inventory",_design.get("module_inventory",{})) as Dictionary).get(id,0))
		for placed in _design.get("module_slots",[]):
			if str(placed)==id: free-=1
		if free<=0: return false
		var index := module_clip_at(global_position, true)
		var slots: Array=_design.get("module_slots",[])
		if index<0 or index>=slots.size() or not str(slots[index]).is_empty(): return false
		_request("install_module",{"slot":index,"module_id":id})
		var current: Array=_design.get("module_slots",[])
		if index>=current.size() or str(current[index])!=id: return false
		_request("move_module",{"slot":index,"position":_neuron.suggested_module_position(index)})
		show_module(id, index)
		return true
	if _tab != "cultivate": return false
	return _context_slice.accept_tabletop_item(kind,id,global_position)


func show_material(kind: String,id: String) -> void:
	if kind=="module":
		select_tab("edit")
		show_module(id)
		return
	select_tab("cultivate")
	var layer: String = {"language":"language","group":"group","topic":"topics","stance_token":"stance","pragmatic_token":"pragmatic"}.get(kind,"")
	if not layer.is_empty(): _context_slice.select_layer(layer)


func _module_content(id: String) -> String:
	return str(_rules.find("modules", id).get("content", ""))

func _show_context_info(info: Dictionary) -> void:
	if _context_title == null: return
	var title := DeskLocalization.text(str(info.get("title",info.get("layer",DeskLocalization.text("LOC_LANGUAGE_9F6FEE1A")))))
	if info.get("resource") is Dictionary and not info.resource.is_empty(): title += " · "+DeskLocalization.text(str(info.resource.get("title","")))
	_context_title.text = DeskLocalization.text("LOC_CONTEXT_5E21ECEB")+title
	_context_details.text = ""
	_context_details.hide()

func _refresh_overview() -> void:
	if _overview_name == null: return
	var raw_name := str(_draft.get("name", _draft.get("title", "")))
	var name := DeskLocalization.text(raw_name) if raw_name == _catalog_default_name else raw_name
	if name.is_empty() and _catalog != null:
		var preset: MemeDemoPreset = _catalog.find_preset(str(_design.get("starter_preset_id", "")))
		if preset != null: name = ExpressionText.preset_name(preset, true)
	if _catalog != null:
		var preset: MemeDemoPreset = _catalog.find_preset(str(_draft.get("preset_id", "")))
		if preset != null and raw_name == preset.title: name = ExpressionText.preset_name(preset, true)
	_overview_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_overview_name.text = name
	var rows := PackedStringArray()
	for pair: Array in [["language", "LOC_LANGUAGE_9F6FEE1A", "○"], ["group", "LOC_EDIT_AUDIENCE", "◇"], ["topics", "LOC_EDIT_TOPICS", "≡"]]:
		var layer: Dictionary = _design.get("context_layers", {}).get(pair[0], {})
		var names := PackedStringArray()
		if bool(layer.get("attached", true)):
			for slot: Dictionary in layer.get("slots", []):
				var id := str(slot.get("resource_id", ""))
				if not id.is_empty(): names.append(DeskLocalization.text(str(_rules.context_resource(id).get("title", id))))
		rows.append("[b]%s %s[/b]  %s" % [pair[2], DeskLocalization.text(pair[1]), _escape(" / ".join(names) if not names.is_empty() else DeskLocalization.text("LOC_NOT_SELECTED_1182C545"))])
	var count := 0
	for id: String in _design.get("module_slots", []):
		if not id.is_empty(): count += 1
	rows.append("[b]%s[/b]  [font_size=22]%d[/font_size] / %d" % [DeskLocalization.text("LOC_EDIT_PATCHES"), count, _physical_clips.size()])
	_overview_data.text = "\n".join(rows)
	_final_expression.text = ExpressionText.render(_catalog, _draft) if _catalog != null else ""
	_final_title.text = DeskLocalization.text("LOC_EDIT_FINAL_EXPRESSION")


func _escape(value: String) -> String:
	return value.replace("[", "[lb]")


func set_context_trial(country_id: String, country_title: String, fitness: Dictionary) -> void:
	if _context_trial != null: _context_trial.set_report(country_id, country_title, fitness, get_draft())

func reset_context_trial() -> void:
	if _context_trial != null: _context_trial.reset()

func context_trial_inspection() -> Dictionary:
	var info: Dictionary = _context_trial.inspection() if _context_trial != null else {}
	info.visible = _context_trial != null and _context_trial.is_visible_in_tree()
	return info

func context_slice() -> Control:
	return _context_slice
