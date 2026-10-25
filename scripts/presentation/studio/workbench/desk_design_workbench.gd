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

const Sketch = preload("res://scripts/presentation/studio/design/desk_neural_sketch.gd")
const DendriteTree = preload("res://scripts/presentation/studio/design/desk_dendrite_tree.gd")
const ContextSlice = preload("res://scripts/presentation/studio/context/desk_context_board.gd")
const ContextTrialSlip = preload("res://scripts/presentation/studio/context/desk_context_trial_slip.gd")
const ModuleClip = preload("res://scripts/presentation/studio/design/desk_module_paper_clip.gd")
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
var _part_content: TextEdit
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
var _overview_data: Label
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
	if _part_edit_identity != identity or not _part_content.has_meta(DeskLocalization.EDIT_META) or DeskLocalization.text_edit_value(_part_content) != value:
		DeskLocalization.bind_text_edit(_part_content,value,authored_default)
		_part_edit_identity = identity
	else:
		DeskLocalization.refresh_edits(_part_content)

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
	button.show()
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
	var relevant := {"design_state":design,"meme_points":snapshot.get("meme_points",0),"phase":snapshot.get("phase","draft"),"lineage":snapshot.get("lineage",[])}
	if _state == relevant: return
	_state=relevant.duplicate(true)
	_design=design.duplicate(true)
	var slots: Array=_design.get("module_slots",[])
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
	if _publish!=null: _publish.visible=id=="edit"
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
		var button:=_button(self,[DeskLocalization.text("编辑"),DeskLocalization.text("培养"),DeskLocalization.text("传播")][index],"Tab"+TABS[index].capitalize())
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
	_part_title=_label(page,"表达模块","PartTitle",17)
	_part_note=_label(page,"点击细胞核、轴突或树突上的表达；将真实获得的补丁拖入图中。","PartDescription",12)
	_part_content=TextEdit.new()
	_part_content.name="PartContent"
	_part_content.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	_part_content.add_theme_font_size_override("font_size",14)
	_part_content.add_theme_color_override("font_color",INK)
	var paper:=StyleBoxFlat.new()
	paper.bg_color=Color("ede8d8")
	paper.content_margin_left=10
	paper.content_margin_right=10
	paper.content_margin_top=8
	_part_content.add_theme_stylebox_override("normal",paper)
	_part_content.add_theme_stylebox_override("focus",paper)
	page.add_child(_part_content)
	DeskLocalization.bind_text_edit(_part_content,"",false)
	_part_content.text_changed.connect(_content_changed)
	_source=RichTextLabel.new()
	_source.name="SourceAndMutation"
	_source.bbcode_enabled=false
	_source.selection_enabled=true
	_source.add_theme_font_size_override("normal_font_size",11)
	_source.add_theme_color_override("default_color",INK)
	page.add_child(_source)
	_overview_name=_label(page,"","MemeOverviewName",15)
	_overview_data=_label(page,"","MemeOverviewData",12)


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
	_context_title = _label(page,"皮层 / 语言","ContextLayerTitle",20)
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
	_skill_title=_label(page,"文本","SkillTitle",18)
	_skill_details=RichTextLabel.new()
	_skill_details.name="SkillDetails"
	_skill_details.bbcode_enabled=false
	_skill_details.add_theme_color_override("default_color",INK)
	_skill_details.add_theme_font_size_override("normal_font_size",14)
	page.add_child(_skill_details)
	_buy=_button(page,"研究此节点","BuySkill")
	_buy.pressed.connect(func() -> void: skill_purchase_requested.emit(_selected_skill))
	_apply_skill=_button(page,"应用能力到草稿","ApplySkill")
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


func _content_changed() -> void:
	if _setting: return
	var content := DeskLocalization.text_edit_value(_part_content)
	if not _selected_module.is_empty():
		_module_edits[_selected_module]=content
		_catalog_default_modules.erase(_selected_module)
		if _selected_installed_slot>=0: _request("edit_module_content",{"slot":_selected_installed_slot,"content":content,"draft":get_draft()})
		return
	if _selected_part.is_empty(): return
	_edited_slots[_selected_part] = true
	_catalog_default_slots.erase(_selected_part)
	var slots: Dictionary=_draft.get("slots",{}).duplicate(true)
	if str(slots.get(_selected_part,""))==content: return
	slots[_selected_part]=content
	_draft.slots=slots
	_refresh_neuron()
	draft_changed.emit(get_draft())


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
	_part_note.text=DeskLocalization.text("修正这里的表达。")
	_part_content.editable=true
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
		_part_content.editable=true
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
		_part_title.text=DeskLocalization.text("传播中的表达")
		_part_note.text=DeskLocalization.text("自己的表达") if bool(variant.get("controlled",false)) else DeskLocalization.text("他人改写")
		_part_content.editable=false
		_bind_part_content(str(variant.get("text","")),"variant:"+id,false)
		_source.text=DeskLocalization.text("由此前表达改写而来。") if not (variant.get("parent_ids",[]) as Array).is_empty() else DeskLocalization.text("独立出现的表达。")
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
		_skill_details.text=DeskLocalization.format_text("%s\n\n效果\n%s\n\n依赖：%s\n消耗 %d Meme\n余额 %d\n%s", [DeskLocalization.text(str(skill.get("description",""))),DeskLocalization.text(str(skill.get("effect_text",skill.get("effect",skill.get("description",""))))),", ".join(dependency_titles) if not dependency_titles.is_empty() else DeskLocalization.text("无"),int(skill.get("cost",0)),int(_state.get("meme_points",0)),DeskLocalization.text("已解锁") if unlocked else (DeskLocalization.text("依赖尚未满足") if not missing.is_empty() else DeskLocalization.text("可解锁"))])
		_buy.disabled=unlocked or not missing.is_empty() or int(_state.get("meme_points",0))<int(skill.get("cost",0))
		_buy.text=DeskLocalization.text("已解锁") if unlocked else DeskLocalization.format_text("消耗 %d Meme / 解锁", int(skill.get("cost",0)))
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


func _layout_edit_sheet(w: float,h: float) -> void:
	var right := w*.57
	_place(_neuron,Rect2(0,4,right-18,h-54))
	var span := w-right
	for index in _physical_clips.size():
		var x := right+float(index)*maxf(60,(span-92)/4.0)
		var y: float = [1.0,7.0,-2.0,5.0,0.0][index]
		_place(_physical_clips[index],Rect2(x,y,96,128))
		_physical_clips[index].rotation = deg_to_rad([-5.0,3.5,-2.0,5.5,-3.5][index])
	_place(_overview_name,Rect2(right,145,span*.48-8,96))
	_place(_overview_data,Rect2(right+span*.48,145,span*.52,96))
	# 按排版后的实际高度安排后续文本，避免较长译文互相覆盖。
	var heading_y := maxf(256, maxf(_overview_name.position.y + _overview_name.size.y, _overview_data.position.y + _overview_data.size.y) + 15)
	_place(_part_title,Rect2(right,heading_y,span,26))
	var note_y := _part_title.position.y + _part_title.size.y + 7
	_place(_part_note,Rect2(right,note_y,span,36))
	var content_y := _part_note.position.y + _part_note.size.y + 9
	_place(_part_content,Rect2(right,content_y,span,maxf(72,h-86-content_y)))
	_place(_source,Rect2(right,h-76,span,26))
	_place(_footer,Rect2(0,h-44,w,40))
	if _publish!=null:
		var key_width := maxf(238, _publish.get_combined_minimum_size().x)
		_place(_publish,Rect2(w-key_width-8,4,key_width,maxf(32,_publish.get_combined_minimum_size().y)))


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
		return DeskLocalization.text("未选择")
	var entry := _rules.find(kind, id)
	return DeskLocalization.text(str(entry.get("title", id)))

func inspection() -> Dictionary:
	return {"tab":_tab,"tabs":TABS,"draft":get_draft(),"neuron":_neuron.inspection(),"design_state":_design.duplicate(true),"sync_count":_sync_count,
		"module_slots":_physical_clips.size(),"skill_count":_skill_buttons.size(),
		"selected_part":_selected_part,"selected_skill":_selected_skill,"selected_module":_selected_module,"selected_variant":_selected_variant,
		"content_editable":_part_content.editable,"source_text":_source.text,"skill_details":_skill_details.text,"buy_disabled":_buy.disabled,"error_text":_errors.text,
		"footer_rect":_footer.get_global_rect(),"part_rect":_part_content.get_global_rect(),"neuron_rect":_neuron.get_global_rect(),
		"starter_options":_starter.item_count,"publication_connected":_publish!=null,"inventory_sources":_design.get("inventory_sources",[]).duplicate(true),
		"context_slice":_context_slice.inspection(),"context_trial":context_trial_inspection(),"culture_instruction_visible":_context_details.is_visible_in_tree(),
		"overview":{"name":_overview_name.text,"data":_overview_data.text,"name_rect":_overview_name.get_global_rect(),"data_rect":_overview_data.get_global_rect()},
		"spread_tree":_spread_tree.inspection(),"module_slot_rects":_physical_clips.map(func(clip: Control)->Rect2:return clip.get_global_rect()),
		"sheet_pages":_pages.keys(),"state_mutation":"signals only; authoritative simulation applies resources"}


func module_clip_parent(slot: int) -> Control:
	return _physical_clips[slot] if slot>=0 and slot<_physical_clips.size() else null


func module_clip_at(point: Vector2) -> int:
	for slot in _physical_clips.size():
		if _physical_clips[slot].accepts(point): return slot
	return -1


func accept_tabletop_item(kind: String,id: String,global_position: Vector2) -> bool:
	if not is_visible_in_tree() or id.is_empty(): return false
	if kind=="module" and _tab=="edit":
		var free:=int((_design.get("available_module_inventory",_design.get("module_inventory",{})) as Dictionary).get(id,0))
		for placed in _design.get("module_slots",[]):
			if str(placed)==id: free-=1
		if free<=0: return false
		for index in _physical_clips.size():
			if not _physical_clips[index].accepts(global_position): continue
			var slots: Array=_design.get("module_slots",[])
			if index>=slots.size() or not str(slots[index]).is_empty(): return false
			_request("install_module",{"slot":index,"module_id":id})
			var current: Array=_design.get("module_slots",[])
			if index>=current.size() or str(current[index])!=id: return false
			_request("move_module",{"slot":index,"position":_neuron.suggested_module_position(index)})
			return true
		return false
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
	var title := DeskLocalization.text(str(info.get("title",info.get("layer",DeskLocalization.text("语言")))))
	if info.get("resource") is Dictionary and not info.resource.is_empty(): title += " · "+DeskLocalization.text(str(info.resource.get("title","")))
	_context_title.text = DeskLocalization.text("语境 / ")+title
	_context_details.text = ""
	_context_details.hide()

func _refresh_overview() -> void:
	if _overview_name == null: return
	var raw_name := str(_draft.get("name",_draft.get("title","")))
	var name := DeskLocalization.text(raw_name) if not _catalog_default_name.is_empty() and raw_name == _catalog_default_name else raw_name
	if name.is_empty() and _catalog != null:
		var preset: MemeDemoPreset = _catalog.find_preset(str(_design.get("starter_preset_id","")))
		if preset != null: name = DeskLocalization.text(str(preset.title))
	var kernel: MemeDemoKernel = _kernel(str(_draft.get("kernel_id","")))
	var base := DeskLocalization.text(kernel.title if kernel != null else str(_draft.get("kernel_id", "")))
	_overview_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_overview_name.text = "MEME\n"+name+DeskLocalization.text("\n基模 · ")+base
	var modules := 0
	for id in _design.get("module_slots",[]):
		if not str(id).is_empty(): modules += 1
	var permission: String = {"allowed":DeskLocalization.text("可重用"),"conditional":DeskLocalization.text("有条件"),"restricted":DeskLocalization.text("限制")}.get(str(_draft.get("reuse_permission","allowed")),DeskLocalization.text("限制"))
	_overview_data.text = DeskLocalization.format_text("模块 %d / 5 · Meme %d\n许可 %s · 可替换 %d项\n重混 %.0f%% · 语境 %.0f%%\n可达 %.0f%% · 识别 %.0f%%\n语言 %s · 群体 %s\n话题 %d / 3", [modules,int(_state.get("meme_points",0)),permission,_draft.get("replaceable_slots",[]).size(),float(_draft.get("remix_cost",0))*100,float(_draft.get("context_dependency",0))*100,float(_draft.get("language_access",0))*100,float(_draft.get("recognizability",0))*100,str(_draft.get("language_id","—")),str(_draft.get("group_id","—")),_draft.get("topic_ids",[]).size()])


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
