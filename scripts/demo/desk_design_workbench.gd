class_name DeskDesignWorkbench
extends Control

signal draft_changed(draft: Dictionary)
signal design_action_requested(action: String, params: Dictionary)
signal skill_purchase_requested(id: String)
signal module_tabletop_requested(module_id: String)
signal material_tabletop_requested(kind: String, id: String)
signal sheet_requested(id: String)
signal module_paper_detached(id: String, global_point: Vector2)
signal context_resource_detached(record: Dictionary, global_point: Vector2)
signal context_layer_detached(record: Dictionary, global_point: Vector2)

const Sketch = preload("res://scripts/demo/desk_neural_sketch.gd")
const DendriteTree = preload("res://scripts/demo/desk_dendrite_tree.gd")
const CultureLayout = preload("res://scripts/demo/desk_culture_layout.gd")
const ContextSlice = preload("res://scripts/demo/desk_context_slice.gd")
const ModuleClip = preload("res://scripts/demo/desk_module_paper_clip.gd")
const PaperStyle = preload("res://scripts/demo/desk_paper_style.gd")
const INK := Color("384238")
const TABS := ["edit", "cultivate", "spread"]
const ASSET_PATHS := {"station":"res://assets/desk/v7/lab_components_front.png","kit":"res://assets/desk/v7/lab_components_front.png",
	"warehouse":"res://assets/desk/v6/module_clip_board.png","modules":"res://assets/desk/v6/neuron_family_bases.png",
	"rack":"res://assets/desk/v6/wall_reagent_rack.png","stand":"res://assets/desk/v6/heating_stand.png"}
const MODULE_REGIONS := {"stance":Rect2(0,0,370,724),"relation":Rect2(370,0,505,724),
	"ritual":Rect2(875,0,440,724),"boundary":Rect2(1315,0,425,724),"shared_world":Rect2(1740,0,432,724)}
const KIT_REGIONS := {"flask":Rect2(158,10,223,263),"mortar":Rect2(1129,87,289,174),"pestle":Rect2(225,279,88,254),
	"rod":Rect2(753,285,30,248),"lamp":Rect2(1173,319,204,212),"lamp_on":Rect2(169,543,203,250),
	"waste":Rect2(663,551,210,249),"bottle":Rect2(1221,548,108,248),"powder_jar":Rect2(156,817,230,187),
	"powder":Rect2(620,850,296,151),"solute":Rect2(1186,825,185,178)}
const STATION_SIZE := Vector2(223,263)
const STATION_GLOBE := Rect2(15,86,193,166)

class ModuleCard extends Button:
	var module_id := ""
	var slot := 0
	var callback: Callable
	var drag_requests := 0
	var _detached_id := ""
	func _get_drag_data(_at_position: Vector2) -> Variant:
		if module_id.is_empty() or not callback.is_valid(): return null
		var id := module_id
		callback.call("remove_module",{"slot":slot})
		if not module_id.is_empty(): return null
		_detached_id = id
		drag_requests += 1
		var preview := Label.new()
		preview.text = "表达补丁"
		preview.custom_minimum_size = Vector2(72,50)
		set_drag_preview(preview)
		return {"type":"design_module","module_id":id,"from_clip":true}
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END and not _detached_id.is_empty():
			if not get_viewport().gui_is_drag_successful():
				callback.call("module_paper_to_table",{"module_id":_detached_id,"global_point":get_global_mouse_position()})
			_detached_id = ""
	func _can_drop_data(_at_position: Vector2,data: Variant) -> bool:
		return callback.is_valid() and module_id.is_empty() and data is Dictionary and str(data.get("type",""))=="design_module"
	func _drop_data(_at_position: Vector2,data: Variant) -> void:
		if _can_drop_data(_at_position,data): callback.call("install_module",{"slot":slot,"module_id":str(data.get("module_id",""))})

class MaterialDrag extends TextureRect:
	signal transfer_started
	var payload: Dictionary = {}
	var switch_to_edit := false
	func _get_drag_data(_at_position: Vector2) -> Variant:
		if payload.is_empty(): return null
		var preview:=TextureRect.new()
		preview.texture=texture
		preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		preview.custom_minimum_size=Vector2(52,48)
		preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		set_drag_preview(preview)
		if switch_to_edit: call_deferred("_notify_transfer")
		return payload.duplicate(true)
	func _notify_transfer() -> void:
		transfer_started.emit()

class ToolDrag extends TextureRect:
	signal released_at(global_point: Vector2)
	var _held := false
	var _origin := Vector2.ZERO
	var _grab := Vector2.ZERO
	var _start := Vector2.ZERO
	var drags := 0
	var _hit_texture: Texture2D
	var _hit_image: Image
	var drop_target: Control
	var drop_guard: Callable
	func _can_drop_data(at_position: Vector2,data: Variant) -> bool:
		if drop_target==null or not data is Dictionary or str(data.get("type",""))!="design_bottle": return false
		if not drop_guard.is_valid() or not drop_guard.call(data): return false
		var global_point:=get_global_transform_with_canvas()*at_position
		var target_point:=drop_target.get_global_transform_with_canvas().affine_inverse()*global_point
		return Rect2(Vector2.ZERO,drop_target.size).has_point(target_point) and drop_target.call("_can_drop_data",target_point,data)
	func _drop_data(at_position: Vector2,data: Variant) -> void:
		if not _can_drop_data(at_position,data): return
		var global_point:=get_global_transform_with_canvas()*at_position
		var target_point:=drop_target.get_global_transform_with_canvas().affine_inverse()*global_point
		drop_target.call("_drop_data",target_point,data)
	func _has_point(point: Vector2) -> bool:
		if texture==null or not Rect2(Vector2.ZERO,size).has_point(point): return false
		if _hit_texture!=texture:
			_hit_texture=texture
			_hit_image=texture.atlas.get_image().get_region(texture.region) if texture is AtlasTexture else texture.get_image()
		if _hit_image==null or _hit_image.is_empty(): return false
		var source:=Vector2(_hit_image.get_size())
		var scale_factor:=minf(size.x/source.x,size.y/source.y)
		var fitted:=Rect2((size-source*scale_factor)*.5,source*scale_factor)
		if not fitted.has_point(point): return false
		var pixel: Vector2=(point-fitted.position)/scale_factor
		return _hit_image.get_pixel(clampi(int(pixel.x),0,_hit_image.get_width()-1),clampi(int(pixel.y),0,_hit_image.get_height()-1)).a>.1
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			var point: Vector2=get_global_transform_with_canvas()*event.position
			if event.pressed:
				_held=true
				_origin=position
				_grab=event.position
				_start=point
			elif _held:
				_held=false
				position=_origin
				if point.distance_to(_start)>=6:
					drags+=1
					released_at.emit(point)
			accept_event()
		elif event is InputEventMouseMotion and _held:
			if (event.button_mask&MOUSE_BUTTON_MASK_LEFT)==0:
				_held=false
				position=_origin
			else:
				var point: Vector2=get_global_transform_with_canvas()*event.position
				position=(get_parent() as CanvasItem).get_global_transform_with_canvas().affine_inverse()*point-_grab
			accept_event()

class LiquidSketch extends Control:
	var ratios: Dictionary = {}
	var title := ""
	var kernel_id := ""
	var nodes: Array = []
	var edges: Array = []
	var neuron_texture: Texture2D
	func _draw() -> void:
		var center:=size*.5
		var radius:=minf(size.x,size.y)*.46
		var total:=0
		for amount in ratios.values(): total+=int(amount)
		if total>0:
			draw_circle(center,radius,Color(.53,.61,.48,.14))
			for index in 4:
				var y:=center.y-radius*.40+index*radius*.32
				draw_line(Vector2(center.x-radius*.66,y),Vector2(center.x+radius*.66,y),Color(.32,.40,.30,.23),.75,true)
		if neuron_texture!=null:
			var fit:=minf(radius*1.75/neuron_texture.get_width(),radius*1.75/neuron_texture.get_height())
			var image_size:=Vector2(neuron_texture.get_size())*fit
			draw_texture_rect(neuron_texture,Rect2(center-image_size*.5,image_size),false,Color(1,1,1,.88))

class RatioChart extends Control:
	var entries: Array = []
	var evaporation: Array = []
	var _hover_rows: Array = []
	func _draw() -> void:
		_hover_rows.clear()
		var font:=get_theme_default_font()
		var total:=0
		for entry in evaporation: total+=int(entry.get("amount",0))
		var ordered:=evaporation.duplicate(true)
		ordered.reverse()
		var pitch:=maxf(50,(size.y-92)/4)
		draw_string(font,Vector2(2,16),"蒸发与配比",HORIZONTAL_ALIGNMENT_LEFT,size.x-4,11,INK)
		for index in ordered.size():
			var entry: Dictionary=ordered[index]
			var fraction:=float(entry.get("amount",0))/maxf(total,1)
			var base:=Vector2(21,53+index*pitch)
			var height:=minf(45,pitch-22)
			draw_line(base,base+Vector2(0,height),Color(INK,.35),.7,true)
			draw_rect(Rect2(base+Vector2(6,height*(1-fraction)),Vector2(17,height*fraction)),Color("879278"))
			draw_string(font,base+Vector2(-18,-5),"%d %s" % [int(entry.get("boiling_order",0)),str(entry.get("title",""))],HORIZONTAL_ALIGNMENT_LEFT,size.x-6,9,INK)
			draw_string(font,base+Vector2(27,height*.65),"%d%%" % roundi(fraction*100),HORIZONTAL_ALIGNMENT_LEFT,44,10,INK)
			_hover_rows.append({"rect":Rect2(0,base.y-18,size.x,pitch),"entry":entry})
		# The arrow rises from the first evaporating reservoir to the last.
		var arrow_x:=size.x-9
		draw_line(Vector2(arrow_x,size.y-45),Vector2(arrow_x,36),Color(INK,.40),.7,true)
		draw_polyline(PackedVector2Array([Vector2(arrow_x-3,42),Vector2(arrow_x,36),Vector2(arrow_x+3,42)]),Color(INK,.4),.7,true)
		if not entries.is_empty():
			var sum:=0
			for entry in entries: sum+=int(entry.get("amount",0))
			for index in entries.size():
				var entry: Dictionary=entries[index]
				var x:=6+index*24
				var fraction:=float(entry.get("amount",0))/maxf(sum,1)
				draw_rect(Rect2(x,size.y-8-24*fraction,14,24*fraction),Color("9d8972"))
				_hover_rows.append({"rect":Rect2(x,size.y-40,22,38),"entry":entry})
	func _get_tooltip(at_position: Vector2) -> String:
		for row in _hover_rows:
			if (row.rect as Rect2).has_point(at_position):
				var entry: Dictionary=row.entry
				return "%s · %d份\n%s" % [str(entry.get("title","")),int(entry.get("amount",0)),str(entry.get("description",""))]
		return ""

class BottleDrop extends Button:
	var slot := 0
	var powder_slot := true
	var callback: Callable
	var bottle_texture: Texture2D
	var fill_fraction := 0.0
	var fill_color := Color("879278")
	func _draw() -> void:
		if bottle_texture==null: return
		var fit:=minf(size.x/bottle_texture.get_width(),size.y/bottle_texture.get_height())
		var bottle_size:=Vector2(bottle_texture.get_size())*fit
		var at:=(size-bottle_size)*.5
		if fill_fraction>0:
			var interior:=Rect2(at+bottle_size*Vector2(.20,.41),bottle_size*Vector2(.59,.45))
			var height:=interior.size.y*clampf(fill_fraction,0,1)
			draw_rect(Rect2(interior.position+Vector2(0,interior.size.y-height),Vector2(interior.size.x,height)),Color(fill_color,.28))
		draw_texture_rect(bottle_texture,Rect2(at,bottle_size),false)
	func _get_drag_data(_at_position: Vector2) -> Variant:
		return {"type":"design_bottle", "slot":slot} if powder_slot else null
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return powder_slot and callback.is_valid() and data is Dictionary and str(data.get("type","")) in ["design_ground","design_mortar_powder"]
	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if not _can_drop_data(_at_position,data): return
		if str(data.get("type",""))=="design_mortar_powder": callback.call("take_ground_fill",{"slot":slot})
		else: callback.call("fill",{"slot":slot,"solute_id":str(data.get("solute_id",""))})

class ActionDrop extends Button:
	var action := "put"
	var callback: Callable
	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and (str(data.get("type",""))=="design_bottle" if action=="put" else str(data.get("type","")) in ["design_bottle","design_ground","design_solute"])
	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if not _can_drop_data(_at_position,data): return
		var source: String="solute" if str(data.get("type",""))=="design_solute" else "ground"
		var params := {"slot":int(data.get("slot",0))} if data.has("slot") else {"source":source,"solute_id":str(data.get("solute_id",""))}
		callback.call(action,params)

class RawSoluteCard extends Button:
	var solute_id := ""
	func _get_drag_data(_at_position: Vector2) -> Variant:
		return {"type":"design_solute","solute_id":solute_id} if not disabled and not solute_id.is_empty() else null

class MortarDrop extends Button:
	var callback: Callable
	func _can_drop_data(_at_position: Vector2,data: Variant) -> bool:
		return data is Dictionary and str(data.get("type",""))=="design_solute"
	func _drop_data(_at_position: Vector2,data: Variant) -> void:
		if _can_drop_data(_at_position,data): callback.call("grind",{"solute_id":str(data.get("solute_id",""))})

class PowderCard extends Button:
	var solute_id := ""
	func _get_drag_data(_at_position: Vector2) -> Variant:
		return {"type":"design_ground", "solute_id":solute_id} if not solute_id.is_empty() else null

var _catalog: Resource
var _rules: Resource
var _draft: Dictionary = {}
var _state: Dictionary = {}
var _design: Dictionary = {}
var _tab := "edit"
var _selected_part := ""
var _selected_module := ""
var _selected_skill := "text"
var _selected_variant := ""
var _pending_mortar_solute := ""
var _interaction_enabled := true
var _selected_bottle := 0
var _setting := false
var _pages: Dictionary = {}
var _tabs: Array[Button] = []
var _neuron: Control
var _starter: OptionButton
var _physical_clips: Array[Control] = []
var _module_cards: Array[Button] = []
var _warehouse: TextureRect
var _part_title: Label
var _part_note: Label
var _part_content: TextEdit
var _tabletop: Button
var _source: RichTextLabel
var _errors: Label
var _footer: Control
var _cost: Label
var _publish: Button
var _tools: Dictionary = {}
var _solvent_buttons: Array[Button] = []
var _bottle_buttons: Array[Button] = []
var _solute: OptionButton
var _powder: PowderCard
var _raw_solute: RawSoluteCard
var _context: OptionButton
var _apply_context: Button
var _solute_tabletop: Button
var _bottle_readout: Label
var _liquid: LiquidSketch
var _ratios: RatioChart
var _skill_buttons: Dictionary = {}
var _skill_title: Label
var _skill_details: RichTextLabel
var _buy: Button
var _apply_skill: Button
var _art: Dictionary = {}
var _physical_targets: Dictionary = {}
var _textures: Dictionary = {}
var _sync_count := 0
var _liquid_rows: Array = []
var _sheet_hosts: Dictionary = {}
var _spread_tree: Control
var _module_edits: Dictionary = {}
var _selected_installed_slot := -1
var _mortar_powder: Control
var _flask_solid: Control
var _remove_module: Button
var _mortar_raw: TextureRect
var _mortar_front: TextureRect
var _clip_fronts: Array[TextureRect] = []
var _culture_physics: Control
var _context_slice: Control
var _context_title: Label
var _context_details: RichTextLabel
var _overview_name: Label
var _overview_data: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()
	resized.connect(_layout)
	select_tab("edit")
	_layout()


func configure(catalog: Resource, rules: Resource = null) -> void:
	_catalog = catalog
	_rules = rules
	if _rules == null and ResourceLoader.exists("res://content/demo/design_rules.tres"):
		_rules = load("res://content/demo/design_rules.tres") as Resource
	if _context_slice != null: _context_slice.configure(_rules)
	_refresh_starters()
	_refresh_skills()
	_refresh_inventory()
	_refresh_neuron()
	load_assets()


func load_assets(textures: Dictionary={},_regions: Dictionary={}) -> void:
	for id in ["warehouse","modules"]:
		if textures.has(id): _textures[id]=textures[id]
		elif ResourceLoader.exists(ASSET_PATHS[id]): _textures[id]=load(ASSET_PATHS[id]) as Texture2D
	_refresh_inventory()
	_refresh_neuron()
	_layout()


func bind_publish(button: Button, cost: Label) -> void:
	_publish=button
	_cost=cost
	button.reparent(_footer)
	PaperStyle.apply_button(button)
	cost.hide()
	button.show()
	_layout()


func set_draft(draft: Dictionary) -> void:
	if _draft == draft: return
	_draft=draft.duplicate(true)
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
	var mortar: Dictionary=_design.get("mortar",{})
	if not _pending_mortar_solute.is_empty() and int(mortar.get("count",0))>0 and str(mortar.get("solute_id",""))==_pending_mortar_solute:
		_pending_mortar_solute=""
	var slots: Array=_design.get("module_slots",[])
	if _selected_installed_slot>=0 and (_selected_installed_slot>=slots.size() or str(slots[_selected_installed_slot]).is_empty()): _selected_installed_slot=-1
	_sync_count+=1
	_refresh_inventory()
	_refresh_neuron()
	_refresh_skills()
	_refresh_culture()
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
		var button:=_button(self,["编辑","培养","传播"][index],"Tab"+TABS[index].capitalize())
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
	_neuron.solid_drop_requested.connect(func(slot: int) -> void: _request("take_apply_context",{"slot":slot}))
	_neuron.context_drop_requested.connect(func(id: String) -> void: _request("apply_context",{"context_id":id}))
	_neuron.variant_selected.connect(_select_variant)
	_neuron.module_position_changed.connect(func(slot: int,point: Vector2) -> void: _request("move_module",{"slot":slot,"position":point}))
	_neuron.solid_id_drop_requested.connect(func(id: String) -> void: _request("take_apply_context",{"solid_id":id}))
	_starter=OptionButton.new()
	_starter.name="StarterConfiguration"
	_starter.disabled=true
	_starter.tooltip_text="来电中已选定的初始模因；这里查看配置，不重复选择。"
	page.add_child(_starter)
	_starter.item_selected.connect(_choose_starter)
	_warehouse=_image(page,"FiniteWarehouse")
	_warehouse.hide()
	for index in 5:
		var card:=ModuleCard.new()
		card.name="ModuleStock%d" % index
		card.slot=index
		card.callback=_request
		card.add_theme_font_size_override("font_size",11)
		card.clip_text=true
		for style in ["normal","hover","pressed","disabled"]: card.add_theme_stylebox_override(style,StyleBoxEmpty.new())
		card.pressed.connect(_choose_module.bind(index))
		page.add_child(card)
		_module_cards.append(card)
		card.hide()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_clip_fronts.append(_image(page,"ClipFront%d" % index))
		_clip_fronts[index].hide()
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
	_part_content.text_changed.connect(_content_changed)
	_remove_module=_button(page,"卸下补丁","RemoveModule")
	_remove_module.hide()
	_remove_module.pressed.connect(func() -> void: if _selected_installed_slot>=0: _request("remove_module",{"slot":_selected_installed_slot}))
	_tabletop=_button(page,"放到桌面","PlaceModuleOnDesk")
	_tabletop.pressed.connect(func() -> void:
		if not _selected_module.is_empty() and int((_design.get("module_inventory",{}) as Dictionary).get(_selected_module,0))>0:
			module_tabletop_requested.emit(_selected_module)
			material_tabletop_requested.emit("module",_selected_module))
	_tabletop.hide()
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


func _can_forward_bottle(data: Dictionary) -> bool:
	if not data.get("slot") is int: return false
	var slot: int=data.slot
	var bottles: Array=_design.get("bottles",[])
	return slot>=0 and slot<bottles.size() and str(bottles[slot].get("state",""))=="filled"


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
	if _starter == null: return
	var chosen:=str(_draft.get("preset_id",""))
	var ids:=PackedStringArray(_field(_rules,"starter_presets",["case_s01","case_r01","case_p01"]))
	_starter.clear()
	for preset in _values(_catalog,"presets"):
		var id:=str(_field(preset,"id",""))
		if id not in ids and id!=chosen: continue
		_starter.add_item(str(_field(preset,"title",id)))
		_starter.set_item_metadata(_starter.item_count-1,id)
		if id==chosen: _starter.select(_starter.item_count-1)


func _choose_starter(index: int) -> void:
	if index<0 or index>=_starter.item_count: return
	var id:=str(_starter.get_item_metadata(index))
	for preset in _values(_catalog,"presets"):
		if str(_field(preset,"id",""))!=id: continue
		var changed:=_draft.duplicate(true)
		changed.kernel_id=str(_field(preset,"kernel_id",""))
		changed.preset_id=id
		changed.target=str(_field(preset,"title",""))
		var slots:=PackedStringArray(_field(preset,"required_slots",[]))
		var defaults:=PackedStringArray(_field(preset,"default_values",[]))
		changed.slots={}
		for slot in slots.size(): changed.slots[slots[slot]]=defaults[slot] if slot<defaults.size() else ""
		changed.replaceable_slots=slots
		set_draft(changed)
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
	_neuron.configure(id,nodes,edges,_draft.get("slots",{}))
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
	if not _selected_module.is_empty():
		_module_edits[_selected_module]=_part_content.text
		if _selected_installed_slot>=0: _request("edit_module_content",{"slot":_selected_installed_slot,"content":_part_content.text,"draft":get_draft()})
		return
	if _selected_part.is_empty(): return
	var slots: Dictionary=_draft.get("slots",{}).duplicate(true)
	if str(slots.get(_selected_part,""))==_part_content.text: return
	slots[_selected_part]=_part_content.text
	_draft.slots=slots
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
	_tabletop.hide()
	if _remove_module!=null: _remove_module.hide()
	var definition:=_module_for_kernel(str(_draft.get("kernel_id","")))
	var title:=_selected_part
	for node in definition.get("neuron_nodes",[]):
		if str(node.get("id",""))==_selected_part: title=str(node.get("title",_selected_part))
	_part_title.text=title
	_part_note.text="修正这里的表达。"
	_part_content.editable=true
	_part_content.text=str((_draft.get("slots",{}) as Dictionary).get(_selected_part,""))
	_source.text=""
	_setting=false


func _refresh_inventory() -> void:
	var slots: Array=_design.get("module_slots",[])
	for index in _module_cards.size():
		var card: ModuleCard=_module_cards[index] as ModuleCard
		card.module_id=str(slots[index]) if index<slots.size() else ""
		card.text=""
		card.disabled=false
		card.icon=null
		card.tooltip_text=""
		card.hide()
		for entry in _values(_rules,"modules"):
			if str(entry.get("id",""))==card.module_id:
				card.icon=_module_texture(str(entry.get("kernel_id","")))
				card.expand_icon=true
				card.add_theme_constant_override("icon_max_width",38)
				card.tooltip_text=str(entry.get("title",""))+"\n"+str(entry.get("description",""))
	_refresh_culture()


func _choose_module(index: int) -> void:
	if index<0 or index>=_module_cards.size(): return
	var id:=(_module_cards[index] as ModuleCard).module_id
	if id.is_empty():
		_selected_installed_slot=-1
		_selected_module=""
		_selected_part=""
		_selected_variant=""
		_setting=true
		_part_title.text="空回形针"
		_part_note.text="夹入一张表达补丁。"
		_part_content.text=""
		_part_content.editable=false
		_source.text=""
		_remove_module.hide()
		_setting=false
		return
	show_module(id,index)


func show_module(id: String,slot: int=-1) -> void:
	_selected_installed_slot=slot
	_selected_module=id
	_selected_variant=""
	for entry in _values(_rules,"modules"):
		if str(entry.id)!=id: continue
		_setting=true
		_part_title.text=str(entry.title)
		_part_note.text=str(entry.description)
		_part_content.editable=true
		var content:=str(_module_edits.get(id,entry.get("content","")))
		if _selected_installed_slot>=0:
			var contents: Array=_design.get("module_contents",[])
			if _selected_installed_slot<contents.size(): content=str(contents[_selected_installed_slot])
		_part_content.text=content
		_tabletop.hide()
		_source.text=""
		if _remove_module!=null: _remove_module.hide()
		_setting=false
		return


func _select_variant(id: String) -> void:
	for variant in _design.get("lineage_view",[]):
		if str(variant.get("id",""))!=id: continue
		_selected_variant=id
		_selected_module=""
		_selected_installed_slot=-1
		_setting=true
		_tabletop.hide()
		if _remove_module!=null: _remove_module.hide()
		_part_title.text="传播中的表达"
		_part_note.text="自己的表达" if bool(variant.get("controlled",false)) else "他人改写"
		_part_content.editable=false
		_part_content.text=str(variant.get("text",""))
		_source.text="由此前表达改写而来。" if not (variant.get("parent_ids",[]) as Array).is_empty() else "独立出现的表达。"
		_setting=false
		return


func _refresh_culture() -> void:
	if _context_slice == null: return
	_context_slice.set_state(_design)
	_show_context_info(_context_slice.selected_info())


func _refresh_solvents() -> void:
	var page: Control=_pages.cultivate
	var solvents:=_values(_rules,"solvents")
	if _solvent_buttons.size()!=solvents.size():
		for button in _solvent_buttons: button.queue_free()
		_solvent_buttons.clear()
		for solvent in solvents:
			var button:=BottleDrop.new()
			button.name="Solvent"+str(solvent.id).capitalize()
			button.powder_slot=false
			button.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
			button.add_theme_stylebox_override("hover",StyleBoxEmpty.new())
			button.add_theme_stylebox_override("pressed",StyleBoxEmpty.new())
			button.add_theme_stylebox_override("disabled",StyleBoxEmpty.new())
			button.bottle_texture=_textures.get("bottle")
			page.add_child(button)
			_label(button,"","BottleLabel",10)
			button.pressed.connect(func() -> void: _request("pour",{"solvent_id":str(solvent.id),"amount":1}))
			_solvent_buttons.append(button)
	for index in solvents.size():
		var solvent: Dictionary=solvents[index]
		var amount:=int((_design.get("solvent_inventory",{}) as Dictionary).get(str(solvent.id),0))
		var capacity:=maxi(1,int(solvent.get("capacity",4)))
		var button: BottleDrop=_solvent_buttons[index] as BottleDrop
		button.text=""
		(button.get_node("BottleLabel") as Label).text="%s\n%d/%d" % [str(solvent.title).trim_suffix("溶剂").trim_suffix("试剂"),amount,capacity]
		button.tooltip_text="%s · 单击倒入 1 份 · 蒸发次序 %d" % [str(solvent.title),int(solvent.get("boiling_order",0))]
		button.fill_fraction=float(amount)/capacity
		button.queue_redraw()
		_solvent_buttons[index].disabled=amount<=0
	_layout()


func _select_bottle(index: int) -> void:
	_selected_bottle=index
	_refresh_culture()


func _selected_solute() -> String:
	return str(_solute.get_item_metadata(_solute.selected)) if _solute!=null and _solute.selected>=0 else ""


func _culture_action(action: String) -> void:
	var params: Dictionary={}
	if action=="grind": params={"solute_id":_selected_solute()}
	elif action=="fill": params={"slot":_selected_bottle,"solute_id":_selected_solute()}
	elif action in ["put","take","discard"]: params={"slot":_selected_bottle}
	_request(action,params)


func _stage_mortar_drop(_action: String,params: Dictionary) -> void:
	var id:=str(params.get("solute_id",""))
	if _culture_physics != null:
		_request("mortar_load",{"solute_id":id})
		return
	if not _pending_mortar_solute.is_empty() or int((_design.get("mortar",{}) as Dictionary).get("count",0))>0: return
	if int((_design.get("solute_inventory",{}) as Dictionary).get(id,0))<=0: return
	_pending_mortar_solute=id
	_refresh_physical_materials()


func staged_raw() -> Dictionary:
	return {"id":_pending_mortar_solute,"count":0 if _pending_mortar_solute.is_empty() else 1}


func staged_raw_id() -> String:
	return _pending_mortar_solute


func cancel_staged_raw() -> void:
	_pending_mortar_solute=""
	_refresh_physical_materials()


func _refresh_physical_materials() -> void:
	if _mortar_powder==null: return
	var mortar: Dictionary=_design.get("mortar",{})
	var amount:=int(mortar.get("count",0))
	_mortar_powder.payload={"type":"design_mortar_powder","solute_id":str(mortar.get("solute_id",""))} if amount>0 else {}
	_mortar_powder.visible=amount>0
	_mortar_powder.tooltip_text="%s粉末 · 拖入空粉瓶" % _entry_title("solutes",str(mortar.get("solute_id","")))
	_mortar_raw.visible=not _pending_mortar_solute.is_empty()
	_mortar_raw.tooltip_text=_entry_title("solutes",_pending_mortar_solute)+" · 等待研磨"
	_flask_solid.payload={}
	for bottle in _design.get("bottles",[]):
		if str(bottle.get("state",""))=="solid":
			_flask_solid.payload={"type":"design_solid","slot":int(bottle.get("slot",0)),"context_id":str(bottle.get("context_id",""))}
			break
	_flask_solid.visible=not _flask_solid.payload.is_empty()
	_flask_solid.tooltip_text="拖到编辑纸的神经元上。"


func _physical_tool_released(point: Vector2,id: String) -> void:
	if id=="pestle" and _inside(_art.mortar,point):
		var solute:=_pending_mortar_solute
		if solute.is_empty(): return
		_request("grind",{"solute_id":solute})
		var mortar: Dictionary=_design.get("mortar",{})
		if int(mortar.get("count",0))>0 and str(mortar.get("solute_id",""))==solute:
			_pending_mortar_solute=""
			_refresh_physical_materials()
	elif id=="rod" and _inside(_liquid,point): _request("stir",{})


func _request(action: String, params: Dictionary) -> void:
	if action == "module_paper_to_table":
		module_paper_detached.emit(str(params.get("module_id","")),params.get("global_point",Vector2.ZERO))
		return
	var request:=params.duplicate(true)
	if action in ["install_module","remove_module","edit_module_content","take_apply_context","apply_context","install_context","remove_context","move_context_axis","detach_context_layer","attach_context_layer"]:
		request["draft"]=get_draft()
		if action=="install_module": request["content"]=str(_module_edits.get(str(request.get("module_id","")),_module_content(str(request.get("module_id","")))))
	design_action_requested.emit(action,request)


func _refresh_skills() -> void:
	if _skill_details==null: return
	var skills:=_values(_rules,"skills")
	for skill in skills:
		var id:=str(skill.id)
		if not _skill_buttons.has(id):
			var button:=_button(_pages.spread,str(skill.title),"Skill"+id.capitalize())
			button.pressed.connect(_select_skill.bind(id))
			_skill_buttons[id]=button
		var unlocked: bool=id in _design.get("unlocked_skills",["text"])
		(_skill_buttons[id] as Button).text=("● " if unlocked else "○ ")+str(skill.title)
		(_skill_buttons[id] as Button).tooltip_text="依赖：%s" % str(skill.get("requires",[]))
	_spread_tree.configure(_values(_rules,"skills"))
	_spread_tree.sync_state(_design.get("unlocked_skills",["text"]),_selected_skill)
	_select_skill(_selected_skill)
	_layout()


func _select_skill(id: String) -> void:
	_selected_skill=id
	if _spread_tree!=null: _spread_tree.sync_state(_design.get("unlocked_skills",["text"]),id)
	for skill in _values(_rules,"skills"):
		if str(skill.id)!=id: continue
		var unlocked: bool=id in _design.get("unlocked_skills",["text"])
		var missing: Array=[]
		for dependency in skill.get("requires",[]):
			if str(dependency) not in _design.get("unlocked_skills",["text"]): missing.append(dependency)
		_skill_title.text=str(skill.title)
		var dependency_titles:=PackedStringArray()
		for dependency in skill.get("requires",[]): dependency_titles.append(_entry_title("skills",str(dependency)))
		_skill_details.text="%s\n\n效果\n%s\n\n依赖：%s\n消耗 %d Meme\n余额 %d\n%s" % [str(skill.get("description","")),str(skill.get("effect_text",skill.get("effect",skill.get("description","")))),"、".join(dependency_titles) if not dependency_titles.is_empty() else "无",int(skill.get("cost",0)),int(_state.get("meme_points",0)),"已解锁" if unlocked else ("依赖尚未满足" if not missing.is_empty() else "可解锁")]
		_buy.disabled=unlocked or not missing.is_empty() or int(_state.get("meme_points",0))<int(skill.get("cost",0))
		_buy.text="已解锁" if unlocked else "消耗 %d Meme / 解锁" % int(skill.get("cost",0))
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
	_warehouse.hide()
	var span := w-right
	for index in _physical_clips.size():
		var x := right+float(index)*maxf(60,(span-92)/4.0)
		var y: float = [1.0,7.0,-2.0,5.0,0.0][index]
		_place(_physical_clips[index],Rect2(x,y,96,128))
		_physical_clips[index].rotation = deg_to_rad([-5.0,3.5,-2.0,5.5,-3.5][index])
		_clip_fronts[index].hide()
	_place(_overview_name,Rect2(right,145,span*.48-8,96))
	_place(_overview_data,Rect2(right+span*.48,145,span*.52,96))
	_place(_part_title,Rect2(right,256,span,26))
	_place(_part_note,Rect2(right,289,span,36))
	_place(_part_content,Rect2(right,334,span,maxf(48,h-412)))
	_place(_source,Rect2(right,h-68,span,42))
	_place(_footer,Rect2(0,h-44,w,40))
	if _publish!=null: _place(_publish,Rect2(w-246,4,238,32))


func _layout_culture_sheet(w: float,h: float) -> void:
	var right := w*.69
	_place(_context_slice,Rect2(0,0,right-20,h))
	_place(_context_title,Rect2(right,25,w-right-12,34))
	_place(_context_details,Rect2(right,78,w-right-12,h-110))


func _layout_spread_sheet(w: float,h: float) -> void:
	var right:=w*.61
	_place(_spread_tree,Rect2(0,0,right-16,h))
	_place(_skill_title,Rect2(right,18,w-right,29))
	_place(_skill_details,Rect2(right,61,w-right,h-135))
	_place(_buy,Rect2(right,h-59,w-right,35))
	_apply_skill.hide()
	for button in _skill_buttons.values(): button.hide()


func _place_bottle_label(bottle: Control) -> void:
	var label: Label=bottle.get_node("BottleLabel")
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.clip_text=true
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",9)
	var powder: bool=(bottle as BottleDrop).powder_slot
	var bounds:=Rect2(bottle.size*Vector2(.12,.40),bottle.size*Vector2(.76,.40)) if powder else Rect2(bottle.size*Vector2(.20,.40),bottle.size*Vector2(.62,.30))
	_place(label,bounds)


func _draw() -> void:
	pass


func _hide_legacy_culture() -> void:
	var physics_chart := _culture_physics.get_node_or_null("EvaporationChart")
	if physics_chart != null: physics_chart.hide()
	for child in _pages.cultivate.get_children():
		if child is CanvasItem and child != _culture_physics and child != _ratios: child.hide()
	if _culture_physics != null: _culture_physics.show()
	_ratios.show()
	_pages.cultivate.move_child(_ratios,_pages.cultivate.get_child_count()-1)


func _refresh_v8_chart() -> void:
	var evaporation: Array = []
	for entry in _values(_rules,"solvents"):
		evaporation.append({"title":str(entry.title),"boiling_order":int(entry.boiling_order),"amount":int((_design.get("chamber_liquid_units",{}) as Dictionary).get(str(entry.id),0)),"description":_natural_solvent_hint(str(entry.id))})
	evaporation.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.boiling_order)<int(b.boiling_order))
	_ratios.evaporation = evaporation
	var amounts: Dictionary = {}
	for list in ["chamber_pending","chamber_dissolved"]:
		for portion in _design.get(list,[]):
			var id := str(portion.get("solute_id",""))
			amounts[id] = int(amounts.get(id,0)) + int(portion.get("quantity_units",0))
	var entries: Array = []
	for id in amounts:
		for entry in _values(_rules,"solutes"):
			if str(entry.id)==str(id): entries.append({"id":id,"title":str(entry.title),"retention_order":int(entry.retention_order),"amount":int(amounts[id]),"description":_natural_context_hint(str(id))})
	entries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.retention_order)>int(b.retention_order))
	_ratios.entries = entries
	_ratios.queue_redraw()


func culture_physics() -> Control:
	return _culture_physics


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_neuron.set_interaction_enabled(enabled and _tab == "edit")
	_spread_tree.set_interaction_enabled(enabled and _tab == "spread")
	if _context_slice != null: _context_slice.set_interaction_enabled(enabled and _tab == "cultivate")


func _process(_delta: float) -> void:
	for id in _pages:
		_suppress_page_tooltips(_pages[id])


func _suppress_page_tooltips(root: Node) -> void:
	if root is Control and root != _ratios: root.tooltip_text = ""
	for child in root.get_children(): _suppress_page_tooltips(child)


func _button(parent: Node,text: String,name: String) -> Button:
	var node:=Button.new()
	node.name=name
	node.text=text
	node.clip_text=true
	node.add_theme_font_size_override("font_size",12)
	parent.add_child(node)
	PaperStyle.apply_button(node)
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
	return node


func _image(parent: Node,name: String) -> TextureRect:
	var node:=TextureRect.new()
	node.name=name
	node.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _place(node: Control,rect: Rect2) -> void:
	node.position=rect.position
	node.size=rect.size


func _fitted_rect(node: TextureRect,source_size: Vector2) -> Rect2:
	var fit:=minf(node.size.x/source_size.x,node.size.y/source_size.y)
	var actual:=source_size*fit
	return Rect2(node.position+(node.size-actual)*.5,actual)


func _field(object: Variant,key: String,fallback: Variant) -> Variant:
	if object is Dictionary: return object.get(key,fallback)
	if object is Object:
		for property in object.get_property_list():
			if str(property.name)==key: return object.get(key)
	return fallback


func _values(object: Variant,key: String) -> Array:
	var value: Variant=_field(object,key,[])
	return value.duplicate(true) if value is Array else Array(value) if value is PackedStringArray else []


func _kernel(id: String) -> Variant:
	for kernel in _values(_catalog,"kernels"):
		if str(_field(kernel,"id",""))==id: return kernel
	return {}


func _module_for_kernel(id: String) -> Dictionary:
	for module in _values(_rules,"modules"):
		if str(module.get("kernel_id",""))==id: return module
	return {}


func _module_texture(id: String) -> Texture2D:
	if not _textures.has("modules") or not MODULE_REGIONS.has(id): return null
	var texture:=AtlasTexture.new()
	texture.atlas=_textures.modules
	texture.region=MODULE_REGIONS[id]
	return texture


func _entry_title(kind: String,id: String) -> String:
	for entry in _values(_rules,kind):
		if str(entry.get("id",""))==id: return str(entry.get("title",id))
	return "未选择" if id.is_empty() else id


func _legacy_context_title(id: String) -> String:
	var parts:=PackedStringArray()
	for solvent in id.get_slice("@",1).split("+",false): parts.append(_entry_title("solvents",solvent))
	return _entry_title("solutes",id.get_slice("@",0)).trim_suffix("溶质")+"培养体 · "+" / ".join(parts)


func _bottle_status(state: String) -> String:
	return {"empty":"空瓶","filled":"已装粉","placed":"已投放","solid":"已蒸干"}.get(state,"未登记状态")


func inspection() -> Dictionary:
	return {"tab":_tab,"tabs":TABS,"draft":get_draft(),"neuron":_neuron.inspection(),"design_state":_design.duplicate(true),"sync_count":_sync_count,
		"module_slots":_physical_clips.size(),"bottle_slots":0,"solvent_count":0,"skill_count":_skill_buttons.size(),
		"selected_part":_selected_part,"selected_skill":_selected_skill,"selected_module":_selected_module,"selected_variant":_selected_variant,
		"content_editable":_part_content.editable,"source_text":_source.text,"skill_details":_skill_details.text,"buy_disabled":_buy.disabled,"error_text":_errors.text,
		"footer_rect":_footer.get_global_rect(),"part_rect":_part_content.get_global_rect(),"neuron_rect":_neuron.get_global_rect(),
		"starter_options":_starter.item_count,"publication_connected":_publish!=null,"inventory_sources":_design.get("inventory_sources",[]).duplicate(true),
		"culture_buttons":{},"culture_physics":false,"chemistry_visible":false,"context_slice":_context_slice.inspection(),
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
		for index in _module_cards.size():
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



func _inside(control: Control,point: Vector2) -> bool:
	return Rect2(Vector2.ZERO,control.size).has_point(control.get_global_transform_with_canvas().affine_inverse()*point)


func show_material(kind: String,id: String) -> void:
	if kind=="module":
		select_tab("edit")
		show_module(id)
		return
	select_tab("cultivate")
	var layer: String = {"language":"language","group":"group","topic":"topics","stance_token":"stance","pragmatic_token":"pragmatic"}.get(kind,"")
	if not layer.is_empty(): _context_slice.select_layer(layer)


func _context_titles() -> PackedStringArray:
	var titles:=PackedStringArray()
	for index in _context.item_count: titles.append(_context.get_item_text(index))
	return titles


func _module_content(id: String) -> String:
	for entry in _values(_rules,"modules"):
		if str(entry.get("id",""))==id: return str(entry.get("content",""))
	return ""


func _natural_context_hint(id: String) -> String:
	return {"observation":"留下可辨认的现场细节。","translation":"让另一种语言也能读懂。","authority":"将表达转向命令与服从。","deliberation":"为商量与回应留下余地。","recontext":"让表达在新的场景中成立。","response":"使回应成为表达的一部分。"}.get(id,"融入自己的表达。")


func _natural_solvent_hint(id: String) -> String:
	return {"language":"语言承载表达。","group":"在社群中寻找共同理解。","topic":"围绕一个话题凝聚。","style":"改变语气与表达质感。"}.get(id,"")


func _show_context_info(info: Dictionary) -> void:
	if _context_title == null: return
	_context_title.text = "皮层 / "+str(info.get("title",info.get("layer","语言")))
	var lines := PackedStringArray()
	for key in ["description","content","hint","instructions"]:
		if info.has(key) and not str(info[key]).is_empty(): lines.append(str(info[key]))
	if info.has("current"):
		lines.append("当前坐标 · "+str(info.current))
		lines.append("起始坐标 · "+str(info.get("origin",[])))
		lines.append("沿一个轴拖动十字，每格一枚；接近起点时退还原筹码。")
	if info.has("resource") and info.resource is Dictionary:
		lines.append(str(info.resource.get("title","")))
		lines.append(str(info.resource.get("description","")))
	if lines.is_empty():
		lines.append("沿刻度选择深度。把对应的物件放到切片上的留位，或拿回桌面。")
	_context_details.text = "\n\n".join(lines)

func _refresh_overview() -> void:
	if _overview_name == null: return
	var name := str(_draft.get("name",_draft.get("title","")))
	if name.is_empty() and _catalog != null:
		var preset: Resource = _catalog.find_preset(str(_design.get("starter_preset_id","")))
		if preset != null: name = str(preset.title)
	var kernel: Variant = _kernel(str(_draft.get("kernel_id","")))
	var base := str(_field(kernel,"title",_draft.get("kernel_id","")))
	_overview_name.text = "MEME\n"+name+"\n基模 · "+base
	var modules := 0
	for id in _design.get("module_slots",[]):
		if not str(id).is_empty(): modules += 1
	var permission: String = {"allowed":"可重用","conditional":"有条件","restricted":"限制"}.get(str(_draft.get("reuse_permission","allowed")),"限制")
	_overview_data.text = "模块 %d / 5 · Meme %d\n许可 %s · 可替换 %d项\n重混 %.0f%% · 语境 %.0f%%\n可达 %.0f%% · 识别 %.0f%%\n语言 %s · 群体 %s\n话题 %d / 3" % [modules,int(_state.get("meme_points",0)),permission,_draft.get("replaceable_slots",[]).size(),float(_draft.get("remix_cost",0))*100,float(_draft.get("context_dependency",0))*100,float(_draft.get("language_access",0))*100,float(_draft.get("recognizability",0))*100,str(_draft.get("language_id","—")),str(_draft.get("group_id","—")),_draft.get("topic_ids",[]).size()]


func context_slice() -> Control:
	return _context_slice
