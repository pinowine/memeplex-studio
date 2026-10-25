## 桌面材料只呈现权威库存，拖放成功后由模拟层决定安装和数量变化。
class_name DeskMaterialCards
extends Control

signal item_clicked(kind: String, id: String)
signal item_dropped(kind: String, id: String, point: Vector2)
signal release_module(slot: int, id: String)

const CardFace := preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
const Interaction = preload("res://scripts/presentation/studio/desk/desk_prop_interaction.gd")
const Paper = preload("res://assets/image/textures/studio/desk/blank_print_paper.png")
const Shade = preload("res://scripts/presentation/studio/desk/desk_object_shadow.gd")
const Hover = preload("res://shaders/ui/desk_torn_hover.gdshader")
const INVENTORIES := {"module":"module_inventory","language":"context_resource_inventory","group":"context_resource_inventory","topic":"context_resource_inventory","stance_token":"context_resource_inventory","pragmatic_token":"context_resource_inventory"}
const ResourceGraphic := preload("res://scripts/presentation/studio/context/desk_context_resource_graphic.gd")
const NeuronGraphic := preload("res://scripts/presentation/studio/design/desk_neuron_graphic.gd")
const CARD_LIMIT := 36
const RewardSlip := preload("res://scripts/presentation/studio/paper/desk_event_material_slip.gd")

class CardInteraction extends DeskPropInteraction:
	signal dropped_at(id: StringName, point: Vector2, origin: Vector2)
	func input_event(event: InputEvent) -> bool:
		var before := inspection()
		var release: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and before.dragging
		var id := StringName(before.pressed)
		var origin: Vector2 = _press_position
		var handled := super.input_event(event)
		if release and handled and inspection().input_diagnostic.last_transition == "drag_released":
			dropped_at.emit(id,event.position,origin)
		return handled

var _rules: MemeDesignRules
var _props: CardInteraction
var _cards: Dictionary = {}
var _design: Dictionary = {}
var _seen: Dictionary = {}
var _seed := -1
var _light: Node2D
var _ink: ShaderMaterial
var _enabled := true
var _last_light := Vector2.ZERO
var _spawn_area := Rect2(844,354,208,260)
var _pending_cards: Dictionary = {}
var _event_positions: Dictionary = {}
var _storage_sections: Dictionary = {}
var _storage_slots: Dictionary = {}
var _event_output_mode := false

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_props = CardInteraction.new()
	_props.name = "MaterialInteractions"
	add_child(_props)
	_props.clicked.connect(_clicked)
	_props.moved.connect(_card_moved)
	_props.hovered.connect(_hovered)
	_props.dropped_at.connect(_released)
	resized.connect(_storage_resized)
	get_window().focus_exited.connect(_return_free_cards)

func configure(rules: MemeDesignRules, light: Node2D, ink: ShaderMaterial) -> void:
	_rules = rules
	_light = light
	_last_light = light.global_position
	_ink = ink
	if _ink != null: _ink.set_shader_parameter("light_position",_light.global_position)
	_build_storage_slots()
	_layout_inventory()

func set_enabled(value: bool) -> void:
	_enabled = value
	_props.set_enabled(value)
	if not value: _return_free_cards()
	for card in _cards.values(): card.node.visible = value
	queue_redraw()

func set_event_output_mode(value: bool) -> void:
	if value == _event_output_mode: return
	_event_output_mode = value
	for card: Dictionary in _cards.values(): card.event_placed = false
	_layout_inventory()
	queue_redraw()

func release_event_cards(_record: Dictionary, _page: Control) -> void:
	# Event rewards remain on their printed sheet until the authority accepts a drag.
	_layout_inventory()

func set_spawn_area(area: Rect2) -> void:
	set_storage_area(area)

func set_storage_area(area: Rect2) -> void:
	if not area.position.is_finite() or not area.size.is_finite() or not area.has_area(): return
	_spawn_area = area
	_build_storage_slots()
	_layout_inventory()
	_layout_pending()
	queue_redraw()

func _storage_resized() -> void:
	_props.set_bounds(Rect2(Vector2.ZERO,size))
	_return_free_cards()

func _storage_ids(kind: String) -> Array[String]:
	var result: Array[String] = []
	if _rules == null: return result
	if kind == "module":
		for entry: Dictionary in _rules.modules: result.append(str(entry.id))
	else:
		var definitions: Resource = _rules.context_definitions
		if definitions != null:
			for entry: Dictionary in definitions.entries:
				if str(entry.kind) == kind: result.append(str(entry.id))
	return result

func _build_storage_slots() -> void:
	_storage_sections.clear()
	_storage_slots.clear()
	var area := _spawn_area.grow(-8)
	var gap := 8.0
	var top := minf(108.0, area.size.y * 0.24)
	var middle := area.size.y * 0.43
	var half := (area.size.x - gap) * 0.5
	_storage_sections.language = Rect2(area.position,Vector2(half,top))
	_storage_sections.group = Rect2(area.position+Vector2(half+gap,0),Vector2(half,top))
	_storage_sections.topic = Rect2(area.position+Vector2(0,top+gap),Vector2(area.size.x,middle))
	var bottom := maxf(44,area.size.y-top-middle-gap*2)
	var pending_height := minf(64,bottom*0.4)
	_storage_sections.module = Rect2(area.position+Vector2(0,top+middle+gap*2),Vector2(area.size.x,bottom-pending_height))
	_storage_sections.pending = Rect2(Vector2(area.position.x,area.end.y-pending_height),Vector2(area.size.x,pending_height))
	for kind: String in ["language","group","topic","module"]:
		var ids := _storage_ids(kind)
		var columns := 6 if kind == "topic" else (5 if kind == "module" else 3)
		var rows := maxi(1,ceili(float(ids.size())/columns))
		var section: Rect2 = _storage_sections[kind]
		var cell := Vector2(section.size.x/columns,maxf(16,section.size.y-25)/rows)
		for index in ids.size():
			var slot := Rect2(section.position+Vector2((index%columns)*cell.x,23+floori(float(index)/columns)*cell.y),cell)
			_storage_slots[kind+"/"+ids[index]] = slot.grow(-3)

func _inventory_position(kind: String, index: int, item_size: Vector2) -> Vector2:
	var ids := _storage_ids(kind)
	if index < 0 or index >= ids.size(): return _spawn_area.position
	var slot: Rect2 = _storage_slots.get(kind+"/"+ids[index],Rect2(_spawn_area.position,item_size))
	return slot.get_center()-item_size*0.5

func _resize_card(card: Dictionary, target: Vector2) -> void:
	var node: Control = card.node
	node.size = target
	node.pivot_offset = target*0.5
	card.paper.size = target
	card.graphic.position = Vector2(4,24)
	card.graphic.size = target-Vector2(8,28)
	if card.has("face"):
		card.face.size = target
		card.face.configure(_physical_face_record(card),get_theme_font("font","Label"))
	card.count.position = Vector2(maxf(0,target.x-24),1)
	card.count.size = Vector2(24,16)
	card.title.position = Vector2(3,2)
	card.title.size = Vector2(maxf(0,target.x-20),23)
	card.title.add_theme_font_size_override("font_size",9)
	card.hover.position = Vector2(-5,-5)
	card.hover.size = target+Vector2(10,10)
	card.hover.material.set_shader_parameter("object_size",target)
	card.hover.material.set_shader_parameter("padding",Vector2(5,5))
	card.hover.material.set_shader_parameter("rect_origin",Vector2(5,5))

func _park_card(key: String) -> void:
	if not _cards.has(key): return
	var card: Dictionary = _cards[key]
	if int(card.get("clipped_slot",-1)) >= 0: return
	if _event_output_mode:
		_park_event_card(key, card)
		return
	var slot: Rect2 = _storage_slots.get(str(card.kind)+"/"+str(card.id),Rect2(_spawn_area.position,Vector2(54,76)))
	var desired := Vector2(56,104) if card.kind == "module" else (Vector2(42,104) if card.kind == "topic" else Vector2(62,62))
	var target := Vector2(maxf(12,minf(desired.x,slot.size.x)),maxf(16,minf(desired.y,slot.size.y)))
	if card.kind in ["language","group"]: target = Vector2.ONE*minf(target.x,target.y)
	_resize_card(card,target)
	card.node.rotation = 0
	card.node.position = slot.get_center()-target*0.5
	card.inventory_position = card.node.position
	card.inventory_docked = true
	_props.register_prop(key,card.node,Rect2(Vector2.ZERO,target),false,true)
	_moved(key,card.node.global_position)

func _physical_face_record(card: Dictionary) -> Dictionary:
	var sources: Array = []
	if str(card.kind) == "module":
		for source: Dictionary in _design.get("inventory_sources",[]):
			if str(source.get("kind","")) == "module" and str(source.get("id","")) == str(card.id): sources.append(source)
	else:
		for resource: Dictionary in _design.get("resources",[]):
			if str(resource.get("id","")) == str(card.id): sources = resource.get("source_records",[])
	var labels := PackedStringArray()
	for source: Dictionary in sources:
		var label := str(source.get("source_instance_id",""))
		if not label.is_empty() and label not in labels: labels.append(label)
	var quantity := 1 if int(card.get("clipped_slot",-1)) >= 0 else _available(str(card.kind),str(card.id))
	return {"kind":str(card.kind),"id":str(card.id),"title":_title(str(card.kind),str(card.id)),"count":quantity,"source_label":" · ".join(labels),"source_records":sources.duplicate(true)}

func _park_event_card(key: String, card: Dictionary) -> void:
	var target := Vector2(144,78) if card.kind == "topic" else Vector2(112,82)
	_resize_card(card, target)
	if not bool(card.get("event_placed", false)):
		var index := int(card.get("inventory_index", 0))
		var kind_index := maxi(0, ["language", "group", "module", "topic"].find(str(card.kind)))
		card.node.position = _spawn_area.position + Vector2(kind_index * 24 + index * 9, index * 18)
		card.node.rotation = deg_to_rad(float((index + kind_index) % 5 - 2) * 3.0)
		card.event_placed = true
	for row: Dictionary in _design.get("event_materials", []):
		var event_key := _event_key(row)
		if str(row.get("kind", "")) == str(card.kind) and str(row.get("id", "")) == str(card.id) and bool(row.get("claimed", false)) and _event_positions.has(event_key):
			card.node.position = (_event_positions[event_key] as Vector2) - target * .5
			_event_positions.erase(event_key)
	card.inventory_position = card.node.position
	card.inventory_docked = false
	_props.register_prop(key, card.node, Rect2(Vector2.ZERO, target), false, true)
	_moved(key, card.node.global_position)

func _layout_inventory() -> void:
	# Held cards keep their drag transform; resting cards retain their emitted or placed pose.
	var held := str(_props.inspection().pressed) if _props != null else ""
	for key: String in _cards:
		if key != held: _park_card(key)

func _return_free_cards() -> void:
	if _props == null: return
	_props.cancel_drag(&"return_to_storage")
	_layout_inventory()

func _draw() -> void:
	if not _enabled or _event_output_mode: return
	var titles := {"language":"语言盘","group":"群体盘","topic":"话题纸条","module":"表达补丁","pending":"待收录"}
	for kind: String in _storage_sections:
		var rect: Rect2 = _storage_sections[kind]
		draw_rect(Rect2(rect.position+Vector2(2,3),rect.size),Color(0.10,0.08,0.04,0.20))
		# The texture has transparent margins; opaque card stock blocks what lies below.
		draw_rect(rect,Color("c7b99a"))
		draw_texture_rect(Paper,rect,false,Color("d8cdb3"))
		draw_rect(rect,Color(0.25,0.23,0.17,0.55),false,1.0)
		draw_string(get_theme_default_font(),rect.position+Vector2(7,16),DeskLocalization.text(titles[kind]),HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-14,12,Color("3d4032"))
	for key: String in _storage_slots:
		var rect: Rect2 = _storage_slots[key]
		draw_rect(rect,Color(0.30,0.31,0.24,0.13),false,0.8)

func return_to_inventory(kind: String, id: String) -> void:
	# The design editor owns an accepted item; its desktop proxy must not cover it.
	var key := kind + "/" + id
	var remaining := _available(kind,id)
	if remaining > 0:
		_return_remaining(key, remaining)
		return
	if _cards.has(key): _remove(key)

func _return_remaining(key: String, count: int) -> void:
	if not _cards.has(key): return
	var card: Dictionary = _cards[key]
	card.count.text = "×%d" % count
	# The accepted unit belongs to the slot; remaining stock stays at the drag origin.
	if _event_output_mode and card.get("return_position") is Vector2:
		card.node.global_position = card.return_position
		card.event_placed = true
	_park_card(key)

func _available(kind: String, id: String) -> int:
	if kind != "module":
		for resource: Dictionary in _design.get("resources",[]):
			if str(resource.id)==id and str(resource.kind)==kind: return int(resource.get("available",0))
		return 0
	var inventory: Dictionary = _design.get("available_module_inventory",_design.get("module_inventory",{}))
	var reserved := 0
	for installed in _design.get("module_slots",[]):
		if str(installed)==id: reserved+=1
	return maxi(0,int(inventory.get(id,0))-reserved)

func _free_key(kind: String, id: String) -> String:
	for key in _cards:
		var card: Dictionary = _cards[key]
		if card.kind==kind and card.id==id and int(card.get("clipped_slot",-1))<0: return str(key)
	return ""

func _clipped_key(slot: int) -> String:
	for key in _cards:
		if int(_cards[key].get("clipped_slot",-1))==slot: return str(key)
	return ""

func _installed(id: String) -> bool:
	return id in _design.get("module_slots",[])

func sync_state(state: Dictionary) -> void:
	if _rules == null: return
	var seed := int(state.get("seed",0))
	if seed != _seed:
		clear_cards()
		_seed = seed
	_design = state.get("design_state",{}).duplicate(true)
	var wanted := {}
	var inventory: Dictionary = _design.get("module_inventory",{})
	for id in inventory:
		var count := _available("module",str(id))
		if count<=0: continue
		var key := _free_key("module",str(id))
		if key.is_empty():
			request_item("module",str(id))
			key=_free_key("module",str(id))
		if not key.is_empty():
			wanted[key]=true
			_cards[key].count.text="×%d" % count
	for resource: Dictionary in _design.get("resources",[]):
		var kind := str(resource.kind)
		var id := str(resource.id)
		if kind in ["stance_token","pragmatic_token"]: continue
		if int(resource.get("available",0))<=0: continue
		var key := _free_key(kind,id)
		if key.is_empty():
			request_item(kind,id)
			key=_free_key(kind,id)
		if not key.is_empty():
			wanted[key]=true
			_cards[key].count.text="×%d" % int(resource.available)
	# Keep the same paper alive while an accepted clamp is being attached.
	var slots: Array = _design.get("module_slots",[])
	for slot in slots.size():
		var id := str(slots[slot])
		if id.is_empty(): continue
		var key := _clipped_key(slot)
		if key.is_empty() or _cards[key].id!=id:
			key=_free_key("module",id)
			if key.is_empty():
				request_item("module",id,true)
				key=_free_key("module",id)
		if not key.is_empty(): wanted[key]=true
	for key in _cards.keys():
		if not wanted.has(key): _remove(key)
	_sync_pending_materials()
	_layout_inventory()

func clamp_module(id: String, slot: int, parent: Control, anchor: Vector2) -> bool:
	if parent==null or not _installed(id): return false
	var attached := _clipped_key(slot)
	if not attached.is_empty(): return _cards[attached].id==id
	var key := _free_key("module",id)
	if key.is_empty():
		if not request_item("module",id,true): return false
		key=_free_key("module",id)
	var card: Dictionary = _cards[key]
	var node: Control = card.node
	card.clipped_slot=slot
	card.inventory_docked=false
	_resize_card(card,Vector2(112,94))
	card.anchor=anchor
	var global_scale := node.get_global_transform_with_canvas().get_scale()
	node.reparent(parent,true)
	node.scale=global_scale/parent.get_global_transform_with_canvas().get_scale()
	node.rotation=deg_to_rad(float(slot-2)*1.3)
	node.position=anchor
	if parent.has_method("bring_front"): parent.bring_front()
	card.count.text=""
	_props.register_prop(key,node,Rect2(Vector2.ZERO,node.size),false,true)
	_moved(key,node.global_position)
	return true

func _unclamp(key: String) -> void:
	var card: Dictionary = _cards[key]
	var slot := int(card.clipped_slot)
	var node: Control = card.node
	card.clipped_slot=-1
	var rotation := node.get_global_transform().get_rotation()
	var global_scale := node.get_global_transform().get_scale()
	node.reparent(self,true)
	node.rotation=rotation-get_global_transform().get_rotation()
	node.scale=global_scale/get_global_transform().get_scale()
	release_module.emit(slot,card.id)

func remember_event_position(record: Dictionary, point: Vector2) -> void:
	if not point.is_finite(): return
	_event_positions[_event_key(record)] = get_global_transform_with_canvas().affine_inverse()*point

func discard_event_position(record: Dictionary) -> void:
	_event_positions.erase(_event_key(record))

func _event_key(record: Dictionary) -> String:
	return "%s/%s/%s" % [str(record.get("instance_id", "")), str(record.get("kind", "")), str(record.get("id", ""))]

func _sync_pending_materials() -> void:
	var wanted := {}
	for row: Dictionary in _design.get("event_materials", []):
		var key := _event_key(row)
		if row.get("requested", false) and row.get("pending", false):
			wanted[key] = true
			if not _pending_cards.has(key):
				var slip := RewardSlip.new()
				slip.name = "SealedMaterial"+str(_pending_cards.size())
				add_child(slip)
				slip.size = Vector2(96,68)
				slip.configure(row, self, theme)
				slip.set_interaction_enabled(false)
				_pending_cards[key] = slip
		elif row.get("claimed", false) and _pending_cards.has(key):
			var material_key := str(row.kind)+"/"+str(row.id)
			if _cards.has(material_key):
				_park_card(material_key)
	for key in _pending_cards.keys():
		if not wanted.has(key):
			_pending_cards[key].queue_free()
			_pending_cards.erase(key)
	_layout_pending()

func _layout_pending() -> void:
	var area: Rect2 = _storage_sections.get("pending",Rect2(_spawn_area.position,Vector2(200,64)))
	var index := 0
	for key: String in _pending_cards:
		var slip: Control = _pending_cards[key]
		slip.size = Vector2(minf(96,maxf(24,area.size.x/3.0)),maxf(24,area.size.y-20))
		slip.position = area.position+Vector2((index%3)*area.size.x/3.0,18)
		index += 1

func request_item(kind: String, id: String, installed: bool=false) -> bool:
	if not INVENTORIES.has(kind) or (_available(kind,id)<=0 and not (installed and kind=="module" and _installed(id))): return false
	var key := _free_key(kind,id)
	if not key.is_empty():
		_raise(key)
		return true
	if _cards.size() >= CARD_LIMIT: return false
	key=kind+"/"+id
	while _cards.has(key): key+="/copy"
	_seen[kind+"/"+id]=true
	var node := Control.new()
	node.name = "Material" + str(_cards.size())
	node.mouse_filter = MOUSE_FILTER_IGNORE
	node.size = Vector2(144,78) if kind=="topic" else Vector2(112,82)
	var siblings := 0
	for existing: Dictionary in _cards.values():
		if existing.kind==kind and int(existing.get("clipped_slot",-1))<0: siblings+=1
	node.position = _inventory_position(kind, siblings, node.size)
	node.rotation = deg_to_rad(float((_cards.size()%5)-2)*2)
	node.pivot_offset = node.size*.5
	add_child(node)
	var paper := TextureRect.new()
	paper.texture = Paper
	if kind in ["stance_token","pragmatic_token"]:
		var atlas := AtlasTexture.new()
		atlas.atlas=load("res://assets/image/textures/studio/desk/metal_resources.png")
		var cell := Vector2(0,1) if kind=="group" else (Vector2(1,0) if kind=="pragmatic_token" else Vector2.ZERO)
		atlas.region=Rect2(cell*Vector2(atlas.atlas.get_size())*.5,Vector2(atlas.atlas.get_size())*.5)
		paper.texture=atlas
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.size = node.size
	paper.mouse_filter = MOUSE_FILTER_IGNORE
	if _ink != null and kind in ["module","topic"]: paper.material = _ink.duplicate()
	node.add_child(paper)
	var marks := RewardSlip.CardMarks.new()
	marks.kind = kind
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.add_child(marks)
	paper.modulate = {"language":Color("e2e7dc"),"group":Color("e4d6b6"),"module":Color("dddbe5"),"topic":Color("eee1ba")}.get(kind,Color.WHITE)
	var shadow := Shade.new()
	shadow.z_index = -1
	node.add_child(shadow)
	shadow.configure(paper.texture)
	var graphic: Control = NeuronGraphic.new() if kind=="module" else ResourceGraphic.new()
	graphic.name="Graphic"
	graphic.mouse_filter=MOUSE_FILTER_IGNORE
	graphic.position=Vector2(5,32) if kind=="module" else Vector2.ZERO
	graphic.size=Vector2(86,78) if kind=="module" else node.size
	node.add_child(graphic)
	if kind=="module":
		graphic.configure(id,str(_rules.find("modules",id).get("kernel_id","stance")))
		graphic.grow()
	else:
		graphic.configure(_rules.context_resource(id))
	var title := Label.new()
	title.name = "StoredMaterialTitle"
	title.text = _title(kind,id)
	title.position = Vector2(6,3)
	title.size = Vector2(62,30)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size",11)
	title.add_theme_color_override("font_color",Color("343a30"))
	title.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_child(title)
	var count := Label.new()
	count.position = Vector2(69,3)
	count.add_theme_font_size_override("font_size",12)
	count.add_theme_color_override("font_color",Color("343a30"))
	count.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_child(count)
	var rim := TextureRect.new()
	rim.texture = paper.texture
	rim.position = Vector2(-7,-7)
	rim.size = node.size+Vector2(14,14)
	rim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rim.mouse_filter = MOUSE_FILTER_IGNORE
	rim.z_index = -2
	var material := ShaderMaterial.new()
	material.shader = Hover
	material.set_shader_parameter("source_texture",paper.texture)
	material.set_shader_parameter("object_size",node.size)
	material.set_shader_parameter("padding",Vector2(7,7))
	material.set_shader_parameter("rect_origin",Vector2(7,7))
	material.set_shader_parameter("band_width",6.0)
	rim.material = material
	rim.hide()
	node.add_child(rim)
	var face := CardFace.new()
	face.name = "PhysicalMaterialCardFace"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(face)
	paper.hide()
	marks.hide()
	graphic.hide()
	title.hide()
	count.hide()
	shadow.hide()
	_cards[key] = {"face":face,"node":node,"paper":paper,"shadow":shadow,"hover":rim,"count":count,"title":title,"kind":kind,"id":id,"clipped_slot":-1,"graphic":graphic,"inventory_docked":true,"inventory_position":node.position,"inventory_index":siblings,"event_placed":false,"card_style":{"language":"ruled_language_card","group":"ochre_group_card","module":"graph_patch_card","topic":"horizontal_topic_card"}.get(kind,"material_card")}
	node.visible = _enabled
	node.tooltip_text = ""
	count.text = "×%d" % _available(kind,id)
	_props.register_prop(key,node,Rect2(Vector2.ZERO,node.size),false,true)
	_park_card(key)
	return true

func place_existing_item(kind: String, id: String, point: Vector2) -> bool:
	if not point.is_finite() or not request_item(kind,id): return false
	var key := _free_key(kind,id)
	if _event_output_mode and _cards.has(key):
		_cards[key].node.position = get_global_transform_with_canvas().affine_inverse() * point - _cards[key].node.size * .5
		_cards[key].event_placed = true
	_park_card(key)
	return true

func _title(kind: String, id: String) -> String:
	var entry: Dictionary = _rules.find("modules",id) if kind=="module" else _rules.context_resource(id)
	return str(entry.get("title",id))

func _clicked(key: StringName) -> void:
	if _cards.has(String(key)):
		_raise(String(key))
		var card: Dictionary = _cards[String(key)]
		item_clicked.emit(card.kind,card.id)

func _raise(key: String) -> void:
	var node: Control = _cards[key].node
	node.get_parent().move_child(node,node.get_parent().get_child_count()-1)
	_props.unregister_prop(key)
	_props.register_prop(key,node,Rect2(Vector2.ZERO,node.size),false,true)

func _card_moved(key: StringName, point: Vector2) -> void:
	if _cards.has(String(key)): _cards[String(key)].inventory_docked = false
	_moved(key, point)

func _moved(key: StringName, _point: Vector2) -> void:
	if not _cards.has(String(key)): return
	var card: Dictionary = _cards[String(key)]
	if int(card.get("clipped_slot",-1))>=0 and card.node.position.distance_to(card.anchor)>16:
		_unclamp(String(key))
	var paper: TextureRect = card.paper
	var shadow: DeskObjectShadow = card.shadow
	var center := paper.get_global_transform()*(paper.size*.5)
	shadow.shadow_offset = paper.get_global_transform().affine_inverse().basis_xform((center-_light.global_position).normalized()*Vector2(4,4).length())
	shadow.shadow_blur = 3
	shadow.shadow_opacity = .2
	shadow.ao_strength = .12
	shadow.sync_from(paper)
	shadow.apply_parameters()
	if paper.material is ShaderMaterial: paper.material.set_shader_parameter("light_position",_light.global_position)

func _hovered(key: StringName) -> void:
	for id in _cards:
		_cards[id].hover.hide()
		if _cards[id].has("face"): _cards[id].face.set_hovered(id == String(key) and _enabled)

func _remove(key: String) -> void:
	_props.unregister_prop(key)
	_cards[key].node.queue_free()
	_cards.erase(key)

func clear_cards() -> void:
	for key in _cards.keys(): _remove(key)
	_seen.clear()
	for slip in _pending_cards.values(): slip.queue_free()
	_pending_cards.clear()
	_event_positions.clear()

func _released(key: StringName, point: Vector2, origin: Vector2) -> void:
	if _cards.has(String(key)):
		var card: Dictionary = _cards[String(key)]
		card.return_position = origin
		item_dropped.emit(card.kind,card.id,point)
		# The authority callback may remove or clip the item before it returns.
		if _cards.has(String(key)): _cards[String(key)].erase("return_position")
		_park_card(String(key))

func _process(_delta: float) -> void:
	if _light != null and not _light.global_position.is_equal_approx(_last_light):
		_last_light = _light.global_position
		for id in _cards: _moved(id,_cards[id].node.global_position)

func handles_viewport_point(viewport_point: Vector2) -> bool:
	return _enabled and is_visible_in_tree() and _props != null and _props._hit_prop(viewport_point) != &""

func hover_info(viewport_point: Vector2) -> Dictionary:
	if not _enabled or not is_visible_in_tree(): return {}
	var key := String(_props._hit_prop(viewport_point))
	if not _cards.has(key): return {}
	return details_for_item(str(_cards[key].kind),str(_cards[key].id))

func details_for_item(kind: String,id: String) -> Dictionary:
	var key := kind+"/"+id
	if not _cards.has(key): return {}
	var card: Dictionary = _cards[key]
	var definition: Dictionary = _rules.find("modules",card.id) if card.kind == "module" else _rules.context_resource(card.id)
	var installed: bool = int(card.get("clipped_slot",-1)) >= 0
	var details := {"kind":card.kind,"id":card.id,"title":str(definition.get("title",card.id)),
		"count":_available(card.kind,card.id),"description":str(definition.get("description","")),
		"status":"已安装" if installed else ("桌面卡牌" if _event_output_mode else "收纳中"),
		"gesture":"拖到回形针安装；拖出回形针移除" if card.kind == "module" else "拖到对应空槽安装"}
	var face_record := _physical_face_record(card)
	details.source_label = str(face_record.get("source_label",""))
	details.source_records = face_record.get("source_records",[]).duplicate(true)
	if str(card.id) == "module_boundary": details.unlock_hint = "安装后增加一个语言槽"
	elif str(card.id) == "module_relation": details.unlock_hint = "安装后增加一个人群槽"
	return details

func inspection() -> Dictionary:
	var items := []
	for card in _cards.values():
		items.append({"kind":card.kind,"id":card.id,"rect":card.node.get_global_rect(),"count":card.count.text,"visible":card.node.is_visible_in_tree(),"instance_id":card.node.get_instance_id(),"clipped_slot":int(card.get("clipped_slot",-1)),"parent":str(card.node.get_parent().get_path()),"graphic":card.graphic.inspection(),"global_scale":card.node.get_global_transform_with_canvas().get_scale(),"size":card.node.size,"inventory_docked":bool(card.get("inventory_docked",false)),"inventory_position":card.get("inventory_position",Vector2.ZERO),"card_style":str(card.face.inspection().shape) if card.has("face") else card.get("card_style", "material_card"),"face":card.face.inspection() if card.has("face") else {}})
	return {"items":items,"spawn_area":_spawn_area,"storage_area":_spawn_area,"storage_mode":"event_output_cards" if _event_output_mode else "fixed_typed_slots","storage_sections":_storage_sections.duplicate(),"storage_slots":_storage_slots.duplicate(),"returns_failed_drop":true,"free_placement":_event_output_mode,"pending":_pending_cards.values().map(func(slip): return slip.inspection()),"limit":CARD_LIMIT,"grants_inventory":false,"writes_layout":false,"interaction":_props.inspection()}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_layout_inventory()
		queue_redraw()
