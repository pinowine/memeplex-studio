class_name DeskMaterialCards
extends Control

signal item_clicked(kind: String, id: String)
signal item_dropped(kind: String, id: String, point: Vector2)
signal release_module(slot: int, id: String)

const Interaction = preload("res://scripts/demo/desk_prop_interaction.gd")
const Paper = preload("res://assets/desk/v1/blank_print_paper.png")
const NEURON_PATH := "res://assets/desk/v6/neuron_family_bases.png"
const KIT_PATH := "res://assets/desk/v6/lab_components.png"
const SKETCH_PATH := "res://shaders/desk_sketch_base.gdshader"
const Shade = preload("res://scripts/demo/desk_object_shadow.gd")
const Hover = preload("res://shaders/desk_torn_hover.gdshader")
const NEURON_REGIONS := {"stance":Rect2(0,0,370,724),"relation":Rect2(370,0,505,724),
	"ritual":Rect2(875,0,440,724),"boundary":Rect2(1315,0,425,724),"shared_world":Rect2(1740,0,432,724)}
const INVENTORIES := {"module":"module_inventory","language":"context_resource_inventory","group":"context_resource_inventory","topic":"context_resource_inventory","stance_token":"context_resource_inventory","pragmatic_token":"context_resource_inventory"}
const ResourceGraphic := preload("res://scripts/demo/desk_context_resource_graphic.gd")
const NeuronGraphic := preload("res://scripts/demo/desk_neuron_graphic.gd")
const CARD_LIMIT := 36
const RewardSlip := preload("res://scripts/demo/desk_event_material_slip.gd")

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

var _rules: Resource
var _props: CardInteraction
var _cards: Dictionary = {}
var _design: Dictionary = {}
var _seen: Dictionary = {}
var _seed := -1
var _light: Node2D
var _ink: ShaderMaterial
var _enabled := true
var _neurons: Texture2D
var _kit: Texture2D
var _sketch: Shader
var _last_light := Vector2.ZERO
var _spawn_area := Rect2(844,354,208,260)
var _staged_raw := ""
var _pending_cards: Dictionary = {}
var _event_positions: Dictionary = {}

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_props = CardInteraction.new()
	_props.name = "MaterialInteractions"
	add_child(_props)
	_props.clicked.connect(_clicked)
	_props.moved.connect(_moved)
	_props.hovered.connect(_hovered)
	_props.dropped_at.connect(_released)
	resized.connect(func() -> void: _props.set_bounds(Rect2(Vector2.ZERO,size)))

func configure(rules: Resource, light: Node2D, ink: ShaderMaterial) -> void:
	_rules = rules
	_light = light
	_last_light = light.global_position
	_ink = ink
	if _ink != null: _ink.set_shader_parameter("light_position",_light.global_position)
	_neurons = load(NEURON_PATH)
	_kit = load(KIT_PATH)
	_sketch = load(SKETCH_PATH)

func set_enabled(value: bool) -> void:
	_enabled = value
	_props.set_enabled(value)
	for card in _cards.values(): card.node.visible = value

func set_spawn_area(area: Rect2) -> void:
	_spawn_area = area

func return_to_inventory(kind: String, id: String) -> void:
	# The design editor owns an accepted item; its desktop proxy must not cover it.
	var key := kind + "/" + id
	var remaining := _available(kind,id)
	if kind != "solute" and remaining > 0:
		_return_remaining(key,remaining)
		return
	if kind == "solute" and id == _staged_raw and remaining > 0:
		_return_remaining(key,remaining)
		return
	if _cards.has(key): _remove(key)

func _return_remaining(key: String, count: int) -> void:
	if not _cards.has(key): return
	var card: Dictionary = _cards[key]
	card.count.text = "×%d" % count
	card.node.global_position = card.get("return_position",card.node.global_position)
	_moved(key,card.node.global_position)

func set_staged_raw(id: String) -> void:
	if id == _staged_raw: return
	var previous := _staged_raw
	_staged_raw = id
	for raw in [previous,id]:
		if raw.is_empty(): continue
		var key: String = "solute/" + raw
		if _available("solute",raw) > 0:
			_seen.erase(key)
		elif _cards.has(key):
			_remove(key)
	sync_state({"seed":_seed,"design_state":_design})

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
	card.anchor=anchor
	var global_scale := node.get_global_transform_with_canvas().get_scale()
	node.reparent(parent,true)
	node.scale=global_scale/parent.get_global_transform_with_canvas().get_scale()
	node.rotation=deg_to_rad(float(slot-2)*1.3)
	node.position=anchor
	if parent.has_method("bring_front"): parent.bring_front()
	card.count.text=""
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
				slip.position = _event_positions.get(key,_spawn_area.position+Vector2(0,_pending_cards.size()*22))-slip.size*.5
				slip.set_interaction_enabled(false)
				_pending_cards[key] = slip
		elif row.get("claimed", false) and _pending_cards.has(key):
			var material_key := str(row.kind)+"/"+str(row.id)
			if _cards.has(material_key):
				_cards[material_key].node.position = _pending_cards[key].position
				_moved(material_key,_cards[material_key].node.global_position)
	for key in _pending_cards.keys():
		if not wanted.has(key):
			_pending_cards[key].queue_free()
			_pending_cards.erase(key)

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
	node.size = Vector2(96,116) if kind=="module" else (Vector2(58,140) if kind=="topic" else Vector2(96,96))
	var siblings := 0
	for existing: Dictionary in _cards.values():
		if existing.kind==kind and int(existing.get("clipped_slot",-1))<0: siblings+=1
	var view := get_viewport_rect().size
	var right := view.x-248
	if kind=="module":
		node.position=Vector2(right+(siblings%2)*110,view.y-122-(siblings/2)*12)
	elif kind=="topic":
		node.position=Vector2(view.x-338+siblings*24,view.y-360)
	else:
		node.position=Vector2(right+(siblings%3)*66+(28 if kind=="group" else 0),view.y-462+(20 if kind=="group" else 0))
	node.rotation = deg_to_rad(float((_cards.size()%5)-2)*2)
	node.pivot_offset = node.size*.5
	add_child(node)
	var paper := TextureRect.new()
	paper.texture = Paper
	if kind not in ["module","topic"]:
		var atlas := AtlasTexture.new()
		atlas.atlas=load("res://assets/desk/v10/metal_resources.png")
		var cell := Vector2(0,1) if kind=="group" else (Vector2(1,0) if kind=="pragmatic_token" else Vector2.ZERO)
		atlas.region=Rect2(cell*Vector2(atlas.atlas.get_size())*.5,Vector2(atlas.atlas.get_size())*.5)
		paper.texture=atlas
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.size = node.size
	paper.mouse_filter = MOUSE_FILTER_IGNORE
	if _ink != null and kind in ["module","topic"]: paper.material = _ink.duplicate()
	node.add_child(paper)
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
	title.text = _title(kind,id) if kind=="module" else ""
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
	_cards[key] = {"node":node,"paper":paper,"shadow":shadow,"hover":rim,"count":count,"kind":kind,"id":id,"clipped_slot":-1,"graphic":graphic}
	node.visible = _enabled
	node.tooltip_text = ""
	count.text = "×%d" % _available(kind,id)
	_props.register_prop(key,node,Rect2(Vector2.ZERO,node.size),false,true)
	_moved(key,node.global_position)
	return true

func place_existing_item(kind: String, id: String, point: Vector2) -> bool:
	if not point.is_finite() or not request_item(kind,id): return false
	var key := _free_key(kind,id)
	var node: Control = _cards[key].node
	var local := get_global_transform_with_canvas().affine_inverse()*point
	node.position = local-node.size*.5
	_moved(key,node.global_position)
	return true

func _texture(kind: String, id: String) -> Texture2D:
	var atlas := AtlasTexture.new()
	if kind == "module":
		var kernel: String = str(_rules.find("modules",id).get("kernel_id","stance"))
		atlas.atlas = _neurons
		atlas.region = NEURON_REGIONS.get(kernel,NEURON_REGIONS.stance)
	elif kind == "solvent":
		atlas.atlas = load("res://assets/desk/v7/lab_components_front.png")
		atlas.region = Rect2(1221,548,108,248)
	else:
		atlas.atlas = _kit
		atlas.region = Rect2(1189,832,189,170) if kind == "solute" else Rect2(631,869,275,129)
	return atlas

func _title(kind: String, id: String) -> String:
	var entry: Dictionary = _rules.find("modules",id) if kind=="module" else _rules.context_resource(id)
	return str(entry.get("title",id))

func _description(kind: String, id: String) -> String:
	var entry: Dictionary = _rules.find("modules" if kind == "module" else "solutes",id.get_slice("@",0))
	var gesture: String = {"module":"夹在编辑纸的回形针上，修正表达。", "solute":"放进培养纸的研钵，拖动研杵研磨。", "ground":"放进下层的空粉末瓶。", "context":"送到编辑纸的神经元上。"}.get(kind,"")
	return _title(kind,id) + "\n" + str(entry.get("description","")) + "\n" + gesture

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
	for id in _cards: _cards[id].hover.visible = id == String(key) and _enabled

func _remove(key: String) -> void:
	_props.unregister_prop(key)
	_cards[key].node.queue_free()
	_cards.erase(key)

func clear_cards() -> void:
	for key in _cards.keys(): _remove(key)
	_seen.clear()
	_staged_raw = ""
	for slip in _pending_cards.values(): slip.queue_free()
	_pending_cards.clear()
	_event_positions.clear()

func _released(key: StringName, point: Vector2, origin: Vector2) -> void:
	if _cards.has(String(key)):
		var card: Dictionary = _cards[String(key)]
		card.return_position = origin
		item_dropped.emit(card.kind,card.id,point)

func _process(_delta: float) -> void:
	if _light != null and not _light.global_position.is_equal_approx(_last_light):
		_last_light = _light.global_position
		for id in _cards: _moved(id,_cards[id].node.global_position)

func inspection() -> Dictionary:
	var items := []
	for card in _cards.values():
		items.append({"kind":card.kind,"id":card.id,"rect":card.node.get_global_rect(),"count":card.count.text,"visible":card.node.is_visible_in_tree(),"instance_id":card.node.get_instance_id(),"clipped_slot":int(card.get("clipped_slot",-1)),"parent":str(card.node.get_parent().get_path()),"graphic":card.graphic.inspection(),"global_scale":card.node.get_global_transform_with_canvas().get_scale(),"size":card.node.size})
	return {"items":items,"pending":_pending_cards.values().map(func(slip): return slip.inspection()),"limit":CARD_LIMIT,"staged_raw":_staged_raw,"grants_inventory":false,"writes_layout":false,"interaction":_props.inspection()}
