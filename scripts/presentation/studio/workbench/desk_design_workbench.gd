## Keeps paper interactions separate from the simulation that owns each design.
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
const CardFace = preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
const ModuleClip = preload("res://scripts/presentation/studio/design/desk_module_paper_clip.gd")
const ExpressionText = preload("res://scripts/gameplay/design/meme_expression.gd")
const AnnotatedText = preload("res://scripts/presentation/studio/workbench/desk_annotated_text.gd")
const MemeExpression = preload("res://scripts/presentation/studio/workbench/desk_meme_expression.gd")
const ReceiptHover = preload("res://scripts/presentation/studio/paper/desk_receipt_hover.gd")
const ContextTagFlow = preload("res://scripts/presentation/context/context_tag_flow.gd")
const PaperIcon = preload("res://scripts/presentation/studio/workbench/desk_workbench_icon.gd")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const HEADING_FONT = preload("res://assets/image/fonts/body_semibold_font.tres")
const BODY_FONT = preload("res://assets/image/fonts/development_font.tres")
const INK := Color("384238")
const SECONDARY_INK := Color("594d3f")
const SPACE_WITHIN := 8
const GROUP_SPACING := 16
const SPACE_BETWEEN := 24
const TABS := ["edit", "cultivate", "spread"]
const ASSET_PATHS := {"modules": "res://assets/image/textures/studio/desk/neuron_family_bases.png"}
const MODULE_REGIONS := {
	"stance": Rect2(0, 0, 370, 724),
	"relation": Rect2(370, 0, 505, 724),
	"ritual": Rect2(875, 0, 440, 724),
	"boundary": Rect2(1315, 0, 425, 724),
	"shared_world": Rect2(1740, 0, 432, 724),
}

class LineagePatchFace extends DeskMaterialCardFace:
	var _print_mask: ImageTexture
	var _mask_size := Vector2.ZERO
	var _mask_builds := 0

	func print_mask() -> Texture2D:
		if _print_mask != null and _mask_size == size: return _print_mask
		var layout := _build_layout()
		var body: Rect2 = layout.body
		var outlines: Array[PackedVector2Array] = [outline_for("module", body), outline_for("module", Rect2(body.position + Vector2(1.2, layout.thickness), body.size))]
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s">' % [size.x, size.y]
		for outline: PackedVector2Array in outlines:
			var points := PackedStringArray()
			for point: Vector2 in outline: points.append("%s,%s" % [point.x, point.y])
			svg += '<polygon points="%s" fill="white" stroke="white" stroke-width="1.1"/>' % " ".join(points)
		svg += "</svg>"
		var mask := Image.new()
		mask.load_svg_from_string(svg, 2.0)
		_print_mask = ImageTexture.create_from_image(mask)
		_mask_size = size
		_mask_builds += 1
		return _print_mask

	func inspection() -> Dictionary:
		var result := super.inspection()
		result.mask_builds = _mask_builds
		result.read_only = true
		return result


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
var _module_drop_enabled := false
var _hover_enabled := true
var _setting := false
var _pages: Dictionary = {}
var _tabs: Array[Button] = []
var _neuron: Control
var _starter: OptionButton
var _physical_clips: Array[Control] = []
var _lineage_cards: Array[Control] = []
var _part_title: Label
var _part_note: Label
var _part_content: RichTextLabel
var _final_expression: Control
var _meaning_title: Label
var _meaning: RichTextLabel
var _source_hover: PanelContainer
var _source_hover_records: Array = []
var _composition: Dictionary = {}
var _lineage_preview: Dictionary = {}
var _module_errors := PackedStringArray()
var _module_feedback: Label
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
var _spread_heading: HBoxContainer
var _spread_heading_font: FontVariation
var _spread_heading_labels: Array[Label] = []
var _spread_column_rule: VSeparator
var _skill_heading: HBoxContainer
var _skill_scroll: ScrollContainer
var _skill_content: VBoxContainer
var _skill_effect: RichTextLabel
var _skill_purchase: VBoxContainer
var _skill_cost: Label
var _skill_balance: Label
var _skill_presentation: Dictionary = {}
var _buy: Button
var _apply_skill: Button
var _textures: Dictionary = {}
var _sync_count := 0
var _sheet_hosts: Dictionary = {}
var _spread_tree: Control
var _spread_tree_scroll: ScrollContainer
var _module_edits: Dictionary = {}
var _selected_installed_slot := -1
var _context_slice: Control
var _context_title: Label
var _context_details: RichTextLabel
var _context_trial: Control
var _overview_name: Label
var _overview_data: GridContainer
var _summary_cells: Dictionary = {}
var _summary_text := ""
var _patch_summary: RichTextLabel
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
	for label: Label in _pages.spread.find_children("*", "Label", true, false):
		if label.has_meta("spread_caption"): label.text = DeskLocalization.text(str(label.get_meta("spread_caption")))
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
		_selected_module = ""
		_selected_variant = ""
		_selected_installed_slot = -1
		_lineage_preview.clear()
		_show_module_errors(PackedStringArray())
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
	var relevant := {"propagation_delivery":snapshot.get("propagation_delivery", {}),"design_state":design,"meme_points":snapshot.get("meme_points",0),"phase":snapshot.get("phase","draft"),"lineage":snapshot.get("lineage",[]),"publish_count":snapshot.get("publish_count",0),"current_variant_id":snapshot.get("current_variant_id",""),"propagation_research_ready":snapshot.get("propagation_research_ready",false)}
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
	_hide_source_hover()
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
	for index in _rules.module_slots:
		var clip := ModuleClip.new()
		clip.name = "PaperClip%d" % index
		page.add_child(clip)
		_physical_clips.append(clip)
		var external := LineagePatchFace.new()
		external.name = "LineagePatchCard"
		external.configure({"kind":"module", "id":"", "title":""}, get_theme_font("font", "Label"))
		external.pivot_offset = CardFace.minimum_card_size("module") * .5
		external.rotation = deg_to_rad(float(index - 2) * 1.3)
		clip.add_child(external)
		external.hide()
		_lineage_cards.append(external)
		clip.bring_front()
		clip.pressed.connect(func(): module_slots_pressed.emit(module_clips_viewport_rect()))
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.name = "ExpressionDetails"
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_detail_scroll)
	_detail_stack = VBoxContainer.new()
	_detail_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_stack.add_theme_constant_override("separation", GROUP_SPACING)
	_detail_scroll.add_child(_detail_stack)
	var overview := _text_group("MemeOverview")
	_overview_name = _label(overview, "", "MemeOverviewName", 22)
	_overview_name.set_meta("paper_emphasis", true)
	_build_summary(overview)
	_module_feedback = _label(overview, "", "ModuleFeedback", 12)
	_module_feedback.add_theme_color_override("font_color", AnnotatedText.CHANGED_INK)
	_module_feedback.hide()
	var expression := _text_group("Expression")
	_information_rule("OverviewExpressionRule", expression)
	_final_expression = MemeExpression.new()
	_final_expression.name = "FinalExpression"
	expression.add_child(_final_expression)
	_final_expression.source_hovered.connect(_show_source_hover)
	_final_expression.source_hover_ended.connect(_hide_source_hover)
	var meaning := _text_group("Meaning")
	_information_rule("ExpressionMeaningRule", meaning)
	_meaning_title = _section_heading(meaning, "meaning", DeskLocalization.source("LOC_WB_MEANING"), "ExpressionMeaningTitle")
	_meaning = _annotated_readout(meaning, "ExpressionMeaning", 16)
	var legacy := Control.new()
	legacy.name = "SelectionState"
	legacy.hide()
	page.add_child(legacy)
	_patch_summary = _readout(legacy, "PatchSummary", 16)
	_patch_summary.bbcode_enabled = true
	_part_title = _label(legacy, "", "PartTitle", 19)
	_part_note = _label(legacy, "", "PartDescription", 14)
	_part_content = _readout(legacy, "PartContent", 16)
	_source = _readout(legacy, "SourceAndMutation", 13)
	_build_source_hover(page)
	_detail_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: _hide_source_hover())


func _text_group(node_name: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.name = node_name
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", SPACE_WITHIN)
	_detail_stack.add_child(group)
	return group


func _build_summary(parent: Node) -> void:
	_overview_data = GridContainer.new()
	_overview_data.name = "MemeOverviewData"
	_overview_data.columns = 2
	_overview_data.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview_data.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overview_data.add_theme_constant_override("h_separation", GROUP_SPACING)
	_overview_data.add_theme_constant_override("v_separation", SPACE_WITHIN)
	parent.add_child(_overview_data)
	for kind: String in ["language", "group", "topic", "stance", "pragmatic", "spread"]:
		var cell := HBoxContainer.new()
		cell.name = kind.capitalize()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation", SPACE_WITHIN)
		_overview_data.add_child(cell)
		if kind != "spread":
			var tags := ContextTagFlow.new()
			tags.name = "Tags"
			cell.add_child(tags)
			tags.minimum_size_changed.connect(_queue_text_layout)
			_summary_cells[kind] = {"title":"", "value":"", "tags":tags, "control":cell}
			continue
		var icon := _paper_icon(cell, kind)
		icon.custom_minimum_size = Vector2(20, 20)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_theme_constant_override("separation", 0)
		cell.add_child(words)
		var title := _label(words, "", "Category", 12)
		title.add_theme_color_override("font_color", SECONDARY_INK)
		var value := _label(words, "", "Value", 14)
		_summary_cells[kind] = {"title":"", "value":"", "title_label":title, "value_label":value, "control":cell}


func _paper_icon(parent: Node, kind: String) -> Control:
	var icon := PaperIcon.new()
	icon.name = kind.capitalize() + "Icon"
	icon.kind = kind
	parent.add_child(icon)
	return icon


func _section_heading(parent: Node, kind: String, title: String, node_name: String) -> Label:
	var row := HBoxContainer.new()
	row.name = node_name + "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", SPACE_WITHIN)
	parent.add_child(row)
	var icon := _paper_icon(row, kind)
	icon.custom_minimum_size = Vector2(20, 20)
	var label := _label(row, title, node_name, 12)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", SECONDARY_INK)
	return label


func _annotated_readout(parent: Node, node_name: String, font_size: int) -> RichTextLabel:
	var label := AnnotatedText.new()
	label.name = node_name
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	label.add_theme_constant_override("line_separation", 6)
	parent.add_child(label)
	label.source_hovered.connect(_show_source_hover)
	label.source_hover_ended.connect(_hide_source_hover)
	return label


func _build_source_hover(page: Control) -> void:
	_source_hover = ReceiptHover.new()
	_source_hover.name = "InlineSourceNote"
	_source_hover.z_index = 20
	page.add_child(_source_hover)
	_source_hover.hide()


func mount_hover_overlay(parent: CanvasLayer, pointer_source: Callable) -> void:
	_source_hover.reparent(parent)
	_source_hover.set_pointer_source(pointer_source)


func _information_rule(node_name: String, parent: Node) -> void:
	var rule := HSeparator.new()
	rule.name = node_name
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size.y = 1
	var pencil := StyleBoxLine.new()
	pencil.color = Color("858571", .55)
	pencil.thickness = 1
	rule.add_theme_stylebox_override("separator", pencil)
	parent.add_child(rule)


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
	var page: Control = _pages.spread
	_spread_heading = _spread_section(page, "spread", "LOC_WB_CAPABILITIES", "SpreadHeading", 20)
	_spread_column_rule = VSeparator.new()
	_spread_column_rule.name = "SpreadColumnRule"
	_spread_column_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pencil := StyleBoxLine.new()
	pencil.vertical = true
	pencil.color = Color("858571", .45)
	pencil.thickness = 1
	_spread_column_rule.add_theme_stylebox_override("separator", pencil)
	page.add_child(_spread_column_rule)
	_spread_tree_scroll = ScrollContainer.new()
	_spread_tree_scroll.name = "SpreadTreeScroll"
	_spread_tree_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_spread_tree_scroll)
	_spread_tree = DendriteTree.new()
	_spread_tree.name = "DendriteTree"
	_spread_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spread_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spread_tree_scroll.add_child(_spread_tree)
	_spread_tree.node_selected.connect(_select_skill)
	_skill_heading = _spread_section(page, "spread", "LOC_TEXT_DD818618", "SkillHeading", 20)
	_skill_heading.minimum_size_changed.connect(_queue_text_layout)
	_skill_title = _skill_heading.get_child(1)
	_skill_title.name = "SkillTitle"
	_skill_scroll = ScrollContainer.new()
	_skill_scroll.name = "SkillScroll"
	_skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_skill_scroll)
	_skill_content = VBoxContainer.new()
	_skill_content.name = "SkillContent"
	_skill_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_content.add_theme_constant_override("separation", GROUP_SPACING)
	_skill_scroll.add_child(_skill_content)
	_skill_details = _readout(_skill_content, "SkillDetails", 16)
	_information_rule("SkillEffectRule", _skill_content)
	_spread_section(_skill_content, "meaning", "LOC_WB_EFFECT", "SkillEffectTitle")
	_skill_effect = _readout(_skill_content, "SkillEffect", 16)
	_skill_purchase = VBoxContainer.new()
	_skill_purchase.name = "SkillPurchase"
	_skill_purchase.add_theme_constant_override("separation", GROUP_SPACING)
	page.add_child(_skill_purchase)
	_skill_purchase.minimum_size_changed.connect(_queue_text_layout)
	_information_rule("PurchaseRule", _skill_purchase)
	var metrics := HBoxContainer.new()
	metrics.name = "SkillMetrics"
	metrics.add_theme_constant_override("separation", GROUP_SPACING)
	_skill_purchase.add_child(metrics)
	_skill_cost = _skill_metric(metrics, "cost", "LOC_WB_COST", "SkillCost")
	_skill_balance = _skill_metric(metrics, "balance", "LOC_WB_BALANCE", "SkillBalance")
	_buy = _button(_skill_purchase, "", "BuySkill")
	_buy.set_meta("disabled_cursor_shape", Control.CURSOR_FORBIDDEN)
	_buy.custom_minimum_size.y = 48
	_spread_button_ink(_buy)
	_buy.pressed.connect(_purchase_selected_skill)
	_apply_skill=_button(page,DeskLocalization.source("LOC_APPLY_ABILITY_TO_DRAFT_DD49D83A"),"ApplySkill")
	_apply_skill.pressed.connect(func() -> void: _request("apply_skill",{"skill_id":_selected_skill}))


func _spread_section(parent: Node, kind: String, key: String, node_name: String, font_size: int = 18) -> HBoxContainer:
	if _spread_heading_font == null:
		_spread_heading_font = HEADING_FONT.duplicate() as FontVariation
		var axes := _spread_heading_font.variation_opentype.duplicate()
		axes[2003265652] = 800.0
		_spread_heading_font.variation_opentype = axes
	var row := HBoxContainer.new()
	row.name = node_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", SPACE_WITHIN)
	parent.add_child(row)
	var icon := _paper_icon(row, kind)
	icon.custom_minimum_size = Vector2(24, 24)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := _label(row, DeskLocalization.text(key), node_name + "Label", font_size)
	title.set_meta("spread_caption", key)
	title.set_meta("paper_section_heading", true)
	title.set_meta("paper_section_font", _spread_heading_font)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", _spread_heading_font)
	_spread_heading_labels.append(title)
	return row


func _skill_metric(parent: Node, kind: String, key: String, node_name: String) -> Label:
	var column := VBoxContainer.new()
	column.name = node_name + "Column"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1
	column.add_theme_constant_override("separation", SPACE_WITHIN)
	parent.add_child(column)
	_spread_section(column, kind, key, node_name + "Heading")
	var value := _label(column, "", node_name, 16)
	value.add_theme_font_override("font", BODY_FONT)
	return value


func _purchase_selected_skill() -> void:
	if not _interaction_enabled or _tab != "spread" or _buy.disabled: return
	skill_purchase_requested.emit(_selected_skill)


func _spread_button_ink(button: Button) -> void:
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, INK)
	button.add_theme_color_override("font_disabled_color", Color(SECONDARY_INK, .65))


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
	var source_slots: Dictionary = ExpressionText.base_slots(_draft)
	_neuron.configure(id,nodes,edges,source_slots)
	var displayed_slots := {}
	for key: String in source_slots:
		var value := str(source_slots[key])
		displayed_slots[key] = DeskLocalization.text(value) if _authored_slot_default(key,value) else value
	_neuron.set_display_slots(displayed_slots)
	_neuron.set_family_texture(_module_texture(id))
	_neuron.set_core_variant(str(_state.get("current_variant_id", "")))
	_neuron.sync_design(_design.get("module_slots",[]),_design.get("connections",[]),_design.get("lineage_view",_state.get("lineage",[])))
	_neuron.set_module_positions(_design.get("module_positions",[]))
	_sync_lineage_clips()
	var current_exists := false
	for node in nodes:
		if str(node.get("id",""))==_selected_part: current_exists=true
	if not current_exists and not nodes.is_empty(): _select_part(str(nodes[0].id))


func _sync_lineage_clips() -> void:
	var lineage: Dictionary = _neuron.lineage_slots()
	for slot in _lineage_cards.size():
		var face: Control = _lineage_cards[slot]
		face.visible = lineage.has(slot)
		_physical_clips[slot].set_meta("external_variant_id", str(lineage[slot].id) if lineage.has(slot) else "")
		if not lineage.has(slot): continue
		var record: Dictionary = lineage[slot]
		var external := str(record.get("source_creator", record.get("creator", "player"))) != "player"
		face.configure({"kind":"module", "id":str(record.id), "title":"LOC_EDIT_EXTERNAL_EXPRESSION" if external else "LOC_YOUR_OWN_EXPRESSION_0A35E8E2", "source_label":str(record.id), "palette":"external" if external else "module", "show_count":false}, get_theme_font("font", "Label"))


func lineage_material_faces() -> Array[Dictionary]:
	var faces: Array[Dictionary] = []
	for slot in _lineage_cards.size():
		var face: Control = _lineage_cards[slot]
		faces.append({"source":face, "key":"lineage/" + str(slot), "owner":null, "visible":face.is_visible_in_tree()})
	return faces


func _lineage_card_inspection() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for slot in _lineage_cards.size():
		var face: Control = _lineage_cards[slot]
		cards.append({"slot":slot, "id":str(_physical_clips[slot].get_meta("external_variant_id", "")), "visible":face.is_visible_in_tree(), "rect":face.get_global_rect(), "instance_id":face.get_instance_id(), "face":face.inspection()})
	return cards


func _select_part(id: String) -> void:
	_selected_part=id
	_selected_module=""
	_selected_variant=""
	_selected_installed_slot=-1
	_lineage_preview.clear()
	_module_errors.clear()
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
	var content := str(ExpressionText.base_slots(_draft).get(_selected_part,""))
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
		_lineage_preview.clear()
		_show_module_errors(_candidate_patch_errors(id, slot))
		_setting=false
		return


func _select_variant(id: String) -> void:
	for variant in _state.get("lineage",_design.get("lineage_view",[])):
		if str(variant.get("id",""))!=id: continue
		_selected_variant=id
		_selected_module=""
		_selected_installed_slot=-1
		_setting=true
		_part_title.text=DeskLocalization.text("LOC_CIRCULATING_EXPRESSION_48990024")
		_part_note.text=DeskLocalization.text("LOC_YOUR_OWN_EXPRESSION_0A35E8E2") if bool(variant.get("controlled",false)) else DeskLocalization.text("LOC_SOMEONE_ELSE_S_REWRITE_90C4EF5E")
		_bind_part_content(str(variant.get("text","")),"variant:"+id,not str(variant.get("meaning_id", "")).is_empty())
		_source.text=DeskLocalization.text("LOC_REWRITTEN_FROM_AN_EARLIER_EXPRESSION_22EA25D8") if not (variant.get("parent_ids",[]) as Array).is_empty() else DeskLocalization.text("LOC_AN_INDEPENDENTLY_EMERGING_EXPRESSION_77A66F57")
		var meaning := str(variant.get("meaning", ""))
		var patches: Array = variant.get("patch_ids", [])
		var patch_titles := PackedStringArray()
		for patch_id: String in patches: patch_titles.append(_entry_title("modules", patch_id))
		if not meaning.is_empty(): _source.text += "\n" + DeskLocalization.text("LOC_WB_MEANING") + "\n" + DeskLocalization.text(meaning)
		_source.text += "\n" + DeskLocalization.format_text("LOC_WB_LINEAGE_PATCHES", [patches.size(), _rules.module_slots, ", ".join(patch_titles) if not patch_titles.is_empty() else DeskLocalization.text("LOC_NONE_484D5561")])
		_lineage_preview = {"id":id, "text":str(variant.get("text", "")), "meaning":meaning, "patch_ids":patches.duplicate(), "parent_ids":variant.get("parent_ids", []).duplicate()}
		_module_errors.clear()
		_setting=false
		return


func _refresh_culture() -> void:
	if _context_slice == null: return
	_context_slice.set_state(_design)
	_show_context_info(_context_slice.selected_info())


func _request(action: String, params: Dictionary) -> void:
	var request:=params.duplicate(true)
	if action in ["install_module", "remove_module"]:
		var errors := _candidate_patch_errors(str(request.get("module_id", "")), int(request.get("slot", -1)), action == "remove_module")
		if not errors.is_empty():
			_show_module_errors(errors)
			return
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
		var unlocked: bool=id in _design.get("unlocked_skills",[])
		(_skill_buttons[id] as Button).text=("● " if unlocked else "○ ")+DeskLocalization.text(str(skill.title))
	_configure_spread_tree()
	_select_skill(_selected_skill, false)
	_layout()


func _configure_spread_tree() -> void:
	_spread_tree.configure(_rules.skills.duplicate(true))
	_spread_tree.sync_state(_design.get("unlocked_skills", []), _selected_skill, bool(_state.get("propagation_research_ready", false)))


func _select_skill(id: String, reveal: bool = true) -> void:
	_selected_skill = id
	var unlocked_ids: Array = _design.get("unlocked_skills", [])
	var skill: Dictionary = _rules.find("skills", id)
	var route := str(skill.get("route", "common"))
	_configure_spread_tree()
	var unlocked := id in unlocked_ids
	var prerequisites_met := _rules.skill_requirements_met(skill, unlocked_ids)
	var research_ready: bool = id == "text" or bool(_state.get("propagation_research_ready", false))
	var balance := int(_state.get("meme_points", 0))
	var cost := int(skill.get("cost", 0))
	_skill_title.text = DeskLocalization.text(str(skill.title))
	_skill_details.text = DeskLocalization.text(str(skill.get("description", "")))
	_skill_effect.text = DeskLocalization.text(str(skill.get("effect_text", "")))
	var delivery: Dictionary = _state.get("propagation_delivery", {})
	if route == "accessibility" and delivery.has("format"):
		var format_key := "LOC_PROP_FORMAT_" + str(delivery.format).to_upper()
		_skill_effect.text += "\n" + DeskLocalization.format_text("LOC_PROP_CURRENT_FORMAT", DeskLocalization.text(format_key))
		var languages := PackedStringArray()
		for language: String in delivery.get("languages", []): languages.append(DeskLocalization.text("LOC_LANGUAGE_" + language.to_upper()))
		if not languages.is_empty(): _skill_effect.text += "\n" + DeskLocalization.format_text("LOC_PROP_COVERED_LANGUAGES", " / ".join(languages))
	_skill_cost.text = "%d MEME" % cost
	_skill_balance.text = "%d MEME" % balance
	var status := "unlocked" if unlocked else ("locked" if not prerequisites_met else ("research_pending" if not research_ready else ("unaffordable" if balance < cost else "available")))
	_skill_balance.add_theme_color_override("font_color", Color("a44635") if not unlocked and balance < cost else INK)
	_buy.disabled = not _interaction_enabled or _tab != "spread" or status != "available"
	_buy.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if _buy.disabled else Control.CURSOR_POINTING_HAND
	_buy.text = "" if unlocked else DeskLocalization.text("LOC_WB_UNLOCK")
	_skill_presentation = {"balance":balance, "cost":cost, "status":status, "route":route, "research_ready":research_ready, "dependencies":skill.get("requires", []).duplicate(), "requires_any":skill.get("requires_any", []).duplicate(), "description":_skill_details.text, "effect":_skill_effect.text}
	_buy.visible = not unlocked
	_apply_skill.hide()
	if reveal: _ensure_spread_skill_visible.call_deferred(id)
	_queue_text_layout()


func _ensure_spread_skill_visible(id: String) -> void:
	var area: Rect2 = _spread_tree.node_rect(id)
	var top := float(_spread_tree_scroll.scroll_vertical)
	var page_height := _spread_tree_scroll.size.y
	if area.position.y < top:
		_spread_tree_scroll.scroll_vertical = floori(area.position.y)
	elif area.end.y > top + page_height:
		_spread_tree_scroll.scroll_vertical = ceili(area.end.y - page_height)




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
	var inset := float(SPACE_BETWEEN)
	var right := w * .52
	var span := w - right - SPACE_WITHIN
	var has_cards := false
	for id: String in _design.get("module_slots", []):
		if not id.is_empty(): has_cards = true
	has_cards = has_cards or not _neuron.lineage_slots().is_empty()
	var clip_height := 128.0 if has_cards else 48.0
	var content_y := 160.0 if has_cards else 144.0
	var clip_step := CardFace.minimum_card_size("module").x + SPACE_WITHIN * 2
	var clip_start := w - inset - 96.0 - clip_step * (_physical_clips.size() - 1)
	_overview_data.columns = 2 if span >= 280 else 1
	_place(_neuron, Rect2(GROUP_SPACING, 144, right - GROUP_SPACING * 2, maxf(100, h - 168)))
	_neuron.show()
	for index in _physical_clips.size():
		var x := clip_start + float(index) * clip_step
		_place(_physical_clips[index], Rect2(x, 6, 96, clip_height))
		_physical_clips[index].rotation = deg_to_rad([-5.0, 3.5, -2.0, 5.5][index])
		_place(_lineage_cards[index], Rect2(Vector2(4, 15), CardFace.minimum_card_size("module")))
	var footer_height := 48.0 if _publish != null and _publish.visible else 0.0
	_place(_detail_scroll, Rect2(right, content_y, span, maxf(78, h - content_y - inset - footer_height)))
	_place(_footer, Rect2(right, h - footer_height, span, footer_height))
	if _publish != null:
		var key_width := maxf(238, _publish.get_combined_minimum_size().x)
		_place(_publish, Rect2(span - key_width, 4, key_width, maxf(32, _publish.get_combined_minimum_size().y)))


func _layout_culture_sheet(w: float,h: float) -> void:
	_context_title.hide()
	_place(_context_slice,Rect2(0,0,w,maxf(240,h)))
	_place(_context_details,Rect2())
	_place(_context_trial,Rect2())
	_context_details.hide()
	_context_trial.hide()

func _layout_spread_sheet(w: float,h: float) -> void:
	var split := w * .60
	var right := split + SPACE_BETWEEN
	var span := w - right - SPACE_BETWEEN
	var top := 144.0
	for title: Label in _spread_heading_labels:
		if title.get_theme_font("font") != _spread_heading_font: title.add_theme_font_override("font", _spread_heading_font)
	for value: Label in [_skill_cost, _skill_balance]:
		if value.get_theme_font("font") != BODY_FONT: value.add_theme_font_override("font", BODY_FONT)
	var tree_top := maxf(top, h * .19)
	_place(_spread_heading, Rect2(SPACE_BETWEEN, tree_top, split - SPACE_BETWEEN * 2, 32))
	_place(_spread_tree_scroll, Rect2(SPACE_BETWEEN, tree_top + 40, split - SPACE_BETWEEN * 2, h - tree_top - 64))
	_spread_tree.custom_minimum_size.y = _spread_tree.content_minimum_height()
	_place(_spread_column_rule, Rect2(split, top, 1, h - top - SPACE_BETWEEN))
	_place(_skill_heading, Rect2(right, top, span, 32))
	var details_y := top + maxf(32, _skill_heading.get_combined_minimum_size().y) + SPACE_BETWEEN
	_skill_purchase.size.x = span
	var purchase_height := maxf(156, _skill_purchase.get_combined_minimum_size().y)
	var purchase_y := h - SPACE_BETWEEN - purchase_height
	_place(_skill_purchase, Rect2(right, purchase_y, span, purchase_height))
	_place(_skill_scroll, Rect2(right, details_y, span, maxf(48, purchase_y - SPACE_BETWEEN - details_y)))
	_apply_skill.hide()
	for button in _skill_buttons.values(): button.hide()


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_neuron.set_interaction_enabled(enabled and _tab == "edit")
	for clip: Control in _physical_clips: clip.set_interaction_enabled(enabled and _tab == "edit")
	_spread_tree.set_interaction_enabled(enabled and _tab == "spread")
	if _context_slice != null: _context_slice.set_interaction_enabled(enabled and _tab == "cultivate")
	_sync_hover_enabled()
	if _buy != null: _select_skill(_selected_skill, false)


func _sync_hover_enabled() -> void:
	var enabled := _hover_enabled and _tab == "edit"
	_final_expression.set_interaction_enabled(enabled)
	_meaning.mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE
	if not enabled: _hide_source_hover()


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
		"lineage_slots":_neuron.lineage_slots(), "lineage_cards":_lineage_card_inspection(),
		"selected_part":_selected_part,"selected_skill":_selected_skill,"selected_module":_selected_module,"selected_variant":_selected_variant,
		"content_editable":false,"final_expression":_final_expression.current_text(),"final_expression_rect":_final_expression.get_global_rect(),"information_sections":4,"source_text":_source.text,"skill_details":_skill_details.text,"buy_disabled":_buy.disabled,"error_text":_errors.text,
		"composition":_composition.duplicate(true),"meaning":_meaning.current_text(),"expression_context":_final_expression.context_text(),"expression_annotations":_final_expression.inspection(),"meaning_annotations":_meaning.inspection(),"context_annotations":{"plain_text":_final_expression.context_text(),"annotations":_final_expression.inspection().context_annotations},"module_errors":_module_errors.duplicate(),"module_availability":module_availability(),
		"source_hover":{"visible":_source_hover.visible,"text":_source_hover.content_text(),"sources":_source_hover_records.duplicate(true),"rect":_source_hover.get_global_rect(),"mouse_filter":_source_hover.mouse_filter,"receipt":_source_hover.inspection()},"neuron_visible":_neuron.is_visible_in_tree(),"part_details_visible":_part_content.is_visible_in_tree(),"language_selector_visible":false,"specimen_art":{"visible":false},
		"footer_rect":_footer.get_global_rect(),"part_rect":_part_content.get_global_rect(),"neuron_rect":_neuron.get_global_rect(),
		"starter_options":_starter.item_count,"publication_connected":_publish!=null,"inventory_sources":_design.get("inventory_sources",[]).duplicate(true),
		"context_slice":_context_slice.inspection(),"context_trial":context_trial_inspection(),"culture_instruction_visible":_context_details.is_visible_in_tree(),
		"overview":{"name":_overview_name.text,"data":_summary_text,"columns":_overview_data.columns,"cells":_summary_inspection(),"name_rect":_overview_name.get_global_rect(),"data_rect":_overview_data.get_global_rect()},
		"spread_tree":_spread_tree.inspection(),"spread_layout":_spread_layout_inspection(),"module_slot_rects":_physical_clips.map(func(clip: Control)->Rect2:return clip.get_global_rect()),
		"sheet_pages":_pages.keys(),"state_mutation":"signals only; authoritative simulation applies resources"}


func set_hover_enabled(enabled: bool) -> void:
	if _hover_enabled == enabled: return
	_hover_enabled = enabled
	_sync_hover_enabled()


func _spread_layout_inspection() -> Dictionary:
	var result := _skill_presentation.duplicate(true)
	result.merge({"single_tree":true,"visible_skill_ids":_spread_tree._points.keys(),"tree_rect":_spread_tree.get_global_rect(), "tree_scroll_rect":_spread_tree_scroll.get_global_rect(), "tree_scroll_vertical":_spread_tree_scroll.scroll_vertical, "tree_scroll_horizontal_disabled":_spread_tree_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "heading_rect":_skill_heading.get_global_rect(),
		"column_rule_rect":_spread_column_rule.get_global_rect(), "details_scroll_rect":_skill_scroll.get_global_rect(),
		"purchase_rect":_skill_purchase.get_global_rect(), "buy_rect":_buy.get_global_rect(),
		"icon_sections":5, "instruction_text_visible":false, "body_font_size":_skill_details.get_theme_font_size("normal_font_size"),
		"title_font":_skill_title.get_theme_font("font").resource_path, "buy_text":_buy.text,
		"status_text_visible":false, "prerequisites_visible":false, "scroll_horizontal_disabled":_skill_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED})
	return result


func hover_info(viewport_point: Vector2) -> Dictionary:
	if not _hover_enabled or _tab != "edit" or not _pages.edit.is_visible_in_tree(): return {}
	var slot := module_clip_at(viewport_point)
	var lineage: Dictionary = _neuron.lineage_slots()
	if lineage.has(slot): return _variant_hover(lineage[slot])
	return {}


func _full_variant(record: Dictionary) -> Dictionary:
	for variant: Dictionary in _state.get("lineage", []):
		if str(variant.id) == str(record.id): return variant
	return record


func _variant_hover(record: Dictionary) -> Dictionary:
	var external_rewrite := str(record.get("source_creator", record.get("creator", "player"))) != "player"
	record = _full_variant(record)
	var text := str(record.get("text", ""))
	var meaning := str(record.get("meaning", ""))
	if not str(record.get("meaning_id", "")).is_empty():
		text = DeskLocalization.text(text)
		meaning = DeskLocalization.text(meaning)
	var description := DeskLocalization.text("LOC_REWRITTEN_FROM_AN_EARLIER_EXPRESSION_22EA25D8" if not (record.get("parent_ids", []) as Array).is_empty() else "LOC_AN_INDEPENDENTLY_EMERGING_EXPRESSION_77A66F57")
	var note := DeskLocalization.text("LOC_CIRCULATING_EXPRESSION_48990024") + "\n" + text + ("\n" + meaning if not meaning.is_empty() else "")
	var title := DeskLocalization.text("LOC_SOMEONE_ELSE_S_REWRITE_90C4EF5E" if external_rewrite else "LOC_YOUR_OWN_EXPRESSION_0A35E8E2")
	return {"kind":"source", "id":str(record.id), "title":title, "description":description, "hover_description":description, "hover_note":note}


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


func set_module_drop_enabled(enabled: bool) -> void:
	_module_drop_enabled = enabled


func can_place_module(id: String, global_position: Vector2) -> bool:
	if not is_visible_in_tree() or id.is_empty() or _tab != "edit": return false
	if not _candidate_patch_errors(id).is_empty(): return false
	var free := int((_design.get("available_module_inventory", _design.get("module_inventory", {})) as Dictionary).get(id, 0))
	for placed in _design.get("module_slots", []):
		if str(placed) == id: free -= 1
	if free <= 0: return false
	var index := module_clip_at(global_position, true)
	var slots: Array = _design.get("module_slots", [])
	return index >= 0 and index < slots.size() and str(slots[index]).is_empty()


func accept_tabletop_item(kind: String,id: String,global_position: Vector2) -> bool:
	if not is_visible_in_tree() or id.is_empty(): return false
	if kind=="module" and _tab=="edit":
		if not _interaction_enabled and not _module_drop_enabled: return false
		if not _candidate_patch_errors(id).is_empty():
			if module_clip_at(global_position) >= 0 and not _rules.find("modules", id).is_empty(): show_module(id)
			return false
		if not can_place_module(id, global_position): return false
		var index := module_clip_at(global_position, true)
		_request("install_module",{"slot":index,"module_id":id})
		var current: Array=_design.get("module_slots",[])
		if index>=current.size() or str(current[index])!=id: return false
		_request("move_module",{"slot":index,"position":_neuron.suggested_module_position(index)})
		show_module(id, index)
		return true
	if not _interaction_enabled or _tab != "cultivate": return false
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
	for pair: Array in [["language", "LOC_LANGUAGE_9F6FEE1A"], ["group", "LOC_EDIT_AUDIENCE"], ["topic", "LOC_EDIT_TOPICS"]]:
		rows.append(_summary_value(pair[0], pair[1], _context_values(pair[0])))
	rows.append(_summary_value("stance", "LOC_WB_IDEOLOGY", _axis_values("stance", "political_position")))
	rows.append(_summary_value("pragmatic", "LOC_PRAGMATICS_7063D1D8", _axis_values("pragmatic", "pragmatic_position")))
	var skills := PackedStringArray()
	for id: String in _design.get("unlocked_skills", []): skills.append(_entry_title("skills", id))
	rows.append(_summary_value("spread", "LOC_SPREAD_1A2DA4D4", skills))
	_summary_text = "\n".join(rows)
	_refresh_composition()


func _summary_value(kind: String, title_key: String, values: PackedStringArray) -> String:
	var title := DeskLocalization.text(title_key)
	var value := " / ".join(values)
	var cell: Dictionary = _summary_cells[kind]
	cell.title = title
	cell.value = value
	if kind == "spread":
		cell.title_label.text = title
		cell.value_label.text = value
	else:
		var tags: Array[Dictionary] = []
		for text: String in values: tags.append({"text":text, "kind":kind, "help":""})
		cell.tags.set_tags(tags)
	return "%s  %s" % [title, value]


func _summary_inspection() -> Dictionary:
	var result := {}
	for kind: String in _summary_cells:
		var cell: Dictionary = _summary_cells[kind]
		result[kind] = {"title":cell.title, "value":cell.value, "rect":cell.control.get_global_rect(), "icon":kind}
		if cell.has("tags"): result[kind].tags = cell.tags.inspection()
	return result


func _refresh_composition() -> void:
	_composition = ExpressionText.compose(_catalog, _draft) if _catalog != null and not _draft.is_empty() else {}
	_hide_source_hover()
	_final_expression.configure(str(_draft.get("preset_id", "")), _composition.get("expression_segments", []), _composition.get("context_segments", []), str(_composition.get("expression", "LOC_WB_NO_COMPOSITION")))
	_meaning.set_segments(_composition.get("meaning_segments", []), str(_composition.get("meaning", "")))
	_meaning_title.text = DeskLocalization.text("LOC_WB_MEANING")
	_meaning_title.visible = not _meaning.get_parsed_text().is_empty()
	_meaning.visible = _meaning_title.visible
	_meaning_title.get_parent().visible = _meaning_title.visible
	_queue_text_layout()


func _context_values(kind: String) -> PackedStringArray:
	var layer := "topics" if kind == "topic" else kind
	if not bool(_draft.get("context_layer_attachment", {}).get(layer, true)):
		return PackedStringArray([DeskLocalization.text("LOC_WB_UNATTACHED")])
	var ids := Array(_draft.get(kind + "_ids", [_draft.get(kind + "_id", "")]))
	var names := PackedStringArray()
	for id: String in ids:
		if id.is_empty(): continue
		var title := DeskLocalization.text(str(_rules.context_resource(kind + "_" + id).get("title", "")))
		if not title.is_empty() and title not in names: names.append(title)
	return names if not names.is_empty() else PackedStringArray([DeskLocalization.text("LOC_NOT_SELECTED_1182C545")])


func _axis_values(kind: String, field: String) -> PackedStringArray:
	if not bool(_draft.get("context_layer_attachment", {}).get(kind, true)):
		return PackedStringArray([DeskLocalization.text("LOC_WB_UNATTACHED")])
	if kind == "stance" and not bool(_draft.get("political_known", false)):
		return PackedStringArray([DeskLocalization.text("LOC_WB_UNSPECIFIED")])
	var value: Variant = _draft.get(field, Vector2.ZERO)
	var point: Vector2 = value if value is Vector2 else Vector2(float(value[0]), float(value[1]))
	var directions := ["freedom", "authority", "equality", "hierarchy"] if kind == "stance" else ["sincere", "ironic", "support", "opposition"]
	var names := PackedStringArray()
	for axis in 2:
		if is_zero_approx(point[axis]): continue
		names.append(_direction_title(directions[axis * 2 + int(point[axis] > 0)]))
	return names if not names.is_empty() else PackedStringArray([DeskLocalization.text("LOC_WB_NEUTRAL")])


func _direction_title(id: String) -> String:
	return DeskLocalization.text({"freedom":"LOC_FREEDOM_D1047EED", "authority":"LOC_AUTHORITY_E9D827BA", "equality":"LOC_EQUALITY_14DD2491", "hierarchy":"LOC_HIERARCHY_33771717", "sincere":"LOC_SINCERITY_8BB7FF57", "ironic":"LOC_IRONY_06D9BA32", "support":"LOC_SUPPORT_D93373F8", "opposition":"LOC_OPPOSITION_454F03C9"}[id])


func _show_source_hover(sources: Array, excerpt: String) -> void:
	if not _hover_enabled or _tab != "edit": return
	_source_hover_records = sources.duplicate(true)
	var rows: Array[Dictionary] = []
	var grouped := {}
	for source: Dictionary in sources:
		var kind := str(source.kind)
		var id := str(source.id)
		var title := ""
		if kind == "patch": title = _entry_title("modules", id)
		elif kind in ["stance", "pragmatic"]: title = _direction_title(id)
		else: title = DeskLocalization.text(str(_rules.context_resource(id).get("title", "")))
		var category := DeskLocalization.text({"patch":"LOC_PATCH_70F56533", "language":"LOC_LANGUAGE_9F6FEE1A", "group":"LOC_EDIT_AUDIENCE", "topic":"LOC_EDIT_TOPICS", "stance":"LOC_WB_IDEOLOGY", "pragmatic":"LOC_PRAGMATICS_7063D1D8"}[kind])
		if not grouped.has(kind): grouped[kind] = {"category":category,"kind":kind,"titles":[]}
		if title not in grouped[kind].titles: grouped[kind].titles.append(title)
	for group: Dictionary in grouped.values():
		var row := {"category":group.category,"value":"\n".join(group.titles),"kind":group.kind}
		if str(group.kind) != "patch":
			var tags: Array[Dictionary] = []
			for text: String in group.titles: tags.append({"text":text, "kind":group.kind, "help":""})
			row.tags = tags
		rows.append(row)
	_source_hover.set_content(DeskLocalization.text("LOC_WB_CHANGED_BY"), rows)
	_source_hover.set_meta("excerpt", excerpt)
	_source_hover.set_width(ReceiptHover.DEFAULT_WIDTH)
	_source_hover.show()
	_source_hover.set_pointer_following(true)


func _hide_source_hover() -> void:
	if _source_hover != null: _source_hover.hide()
	_source_hover_records.clear()


func preview_control() -> Control:
	return _neuron


func summary_control() -> Control:
	return _overview_data


func meaning_control() -> Control:
	return _meaning


func _candidate_patch_errors(id: String, slot: int = -1, removing: bool = false) -> PackedStringArray:
	var candidate: Array = _design.get("module_slots", []).duplicate()
	if slot >= 0 and slot < candidate.size(): candidate[slot] = "" if removing else id
	elif not removing: candidate.append(id)
	return _rules.patch_errors(str(_draft.get("preset_id", "")), candidate)


func _show_module_errors(errors: PackedStringArray) -> void:
	_module_errors = errors.duplicate()
	var translated := PackedStringArray()
	for error: String in errors: translated.append(DeskLocalization.text(error))
	_source.text = "\n".join(translated)
	_module_feedback.text = _source.text
	_module_feedback.visible = not errors.is_empty()
	if not errors.is_empty(): _detail_scroll.ensure_control_visible.call_deferred(_module_feedback)


func module_availability() -> Dictionary:
	var result := {}
	for module: Dictionary in _rules.modules:
		var id := str(module.id)
		var errors := _candidate_patch_errors(id)
		result[id] = {"compatible":errors.is_empty(), "errors":Array(errors)}
	return result


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


