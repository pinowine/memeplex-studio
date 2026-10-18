class_name DeskNeuralSketch
extends Control

signal part_selected(slot_id: String)
signal module_drop_requested(slot: int, module_id: String)
signal connection_requested(from: int, to: int)
signal installed_selected(slot: int, module_id: String)
signal variant_selected(id: String)
signal solid_drop_requested(slot: int)
signal solid_id_drop_requested(id: String)
signal context_drop_requested(id: String)
signal module_position_changed(slot: int, normalized_position: Vector2)

const NeuronSurface=preload("res://scripts/demo/desk_neuron_surface.gd")
const NeuronGeometry=preload("res://scripts/demo/desk_neuron_geometry.gd")
const Metaball = preload("res://shaders/desk_neuron_cells_v9.gdshader")
const BlobFeedback = preload("res://scripts/demo/desk_blob_feedback.gd")
const INK := Color("485046")
const CORE_RADIUS := 22.0
const PATCH_RADIUS := 14.0
const MEMBRANE_BLEND := 14.0
const SHAPES := {"stance":[Vector2(.47,.43),Vector2(.20,.18),Vector2(.51,.85)],
	"relation":[Vector2(.17,.42),Vector2(.83,.43),Vector2(.49,.44)],
	"ritual":[Vector2(.18,.72),Vector2(.46,.43),Vector2(.48,.89)],
	"boundary":[Vector2(.15,.19),Vector2(.24,.84),Vector2(.75,.47)],
	"shared_world":[Vector2(.22,.14),Vector2(.51,.42),Vector2(.46,.86)]}
const NUCLEUS_INDEX := {"stance":0,"relation":2,"ritual":1,"boundary":2,"shared_world":1}

var _kernel_id := ""
var _nodes: Array = []
var _edges: Array = []
var _slots: Dictionary = {}
var _installed: Array = []
var _connections: Array = []
var _lineage: Array = []
var _selected := ""
var _connect_from := -1
var _field: ColorRect
var _material: ShaderMaterial
var _family_art: TextureRect
var _last_drop: Dictionary = {}
var _positions: Array[Vector2] = []
var _bridges: Dictionary = {}
var _feedback := BlobFeedback.new()
var _selected_module := -1
var _interaction_enabled := true
var _pressed_module := -1
var _dragging := false
var _press_point := Vector2.ZERO
var _drag_origin := Vector2.ZERO
var _drag_count := 0
var _cancel_count := 0
var _last_drag: Dictionary = {}
var _neuron_surface: Control
var _cell_growth: Dictionary = {}


func _process(delta: float) -> void:
	var ids: Array = []
	for node: Dictionary in _nodes: ids.append("part:" + str(node.get("id","")))
	for index in _installed.size():
		if not str(_installed[index]).is_empty(): ids.append("module:" + str(index))
	if _feedback.tick(delta,ids): queue_redraw()
	var growing := false
	for id: String in _cell_growth:
		if float(_cell_growth[id])<1.0:
			_cell_growth[id]=move_toward(float(_cell_growth[id]),1.0,maxf(delta,0)*.85)
			growing=true
	if growing:_update_neuronal_network()


func set_interaction_enabled(value: bool) -> void:
	if _interaction_enabled == value: return
	_interaction_enabled = value
	_feedback.set_enabled(value)
	if not value: cancel_module_drag("disabled")
	queue_redraw()


func set_module_positions(positions: Array) -> void:
	if positions.size() != 5: return
	var next: Array[Vector2] = []
	for value: Variant in positions:
		var point := Vector2.ZERO
		if value is Vector2: point = value
		elif value is Array and value.size() == 2 and (value[0] is float or value[0] is int) and (value[1] is float or value[1] is int): point = Vector2(value[0],value[1])
		else: return
		if not is_finite(point.x) or not is_finite(point.y) or point.x < 0 or point.y < 0 or point.x > 1 or point.y > 1: return
		next.append(point)
	_ensure_positions()
	if _pressed_module >= 0: next[_pressed_module] = _positions[_pressed_module]
	if next == _positions: return
	_positions = next
	_update_field()
	queue_redraw()


func select_module(slot: int) -> void:
	_selected_module = slot if slot >= 0 and slot < _installed.size() and not str(_installed[slot]).is_empty() else -1
	_feedback.set_selected("module:" + str(_selected_module) if _selected_module >= 0 else "")
	queue_redraw()


func cancel_module_drag(reason: String = "cancelled") -> void:
	if _pressed_module < 0: return
	_positions[_pressed_module] = _drag_origin
	_last_drag = {"slot":_pressed_module,"committed":false,"reason":reason}
	_cancel_count += 1
	_pressed_module = -1
	_dragging = false
	_feedback.set_pressed("")
	_update_field()
	queue_redraw()


func _ensure_positions() -> void:
	if _positions.size() == 5: return
	_positions.clear()
	for index in 5: _positions.append(Vector2(.18 + .15 * index,.82))


func _hit_id(at: Vector2) -> String:
	for index in _installed.size():
		if not str(_installed[index]).is_empty() and at.distance_to(_module_point(index)) <= 23: return "module:" + str(index)
	for index in _nodes.size():
		if at.distance_to(_point(index)) <= 29: return "part:" + str(_nodes[index].get("id",""))
	return ""


func _on_mouse_exited() -> void:
	_feedback.set_hover("")


func _on_resized() -> void:
	cancel_module_drag("resized")
	_update_field()


func _on_focus_exited() -> void:
	cancel_module_drag("focus_exited")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_field = ColorRect.new()
	_field.name = "NaturalModuleJoin"
	_field.visible=false
	_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material = ShaderMaterial.new()
	_material.shader = Metaball
	_field.material = _material
	add_child(_field)
	_field.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_family_art=TextureRect.new()
	_family_art.name="GeneratedKernelSketch"
	_family_art.visible=false
	_family_art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_family_art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_family_art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_family_art.modulate=Color.WHITE
	var pencil:=ShaderMaterial.new()
	pencil.shader=preload("res://shaders/desk_sketch_base.gdshader")
	_family_art.material=pencil
	_family_art.show_behind_parent=true
	add_child(_family_art)
	_family_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_neuron_surface=NeuronSurface.new()
	_neuron_surface.name="SharedNeuronalNetwork"
	_neuron_surface.show_behind_parent=true
	add_child(_neuron_surface)
	_neuron_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_positions()
	resized.connect(_on_resized)
	mouse_exited.connect(_on_mouse_exited)
	get_window().focus_exited.connect(_on_focus_exited)
	tooltip_text = ""
	_update_field()


func configure(kernel_id: String, nodes: Array, edges: Array, slots: Dictionary) -> void:
	_kernel_id = kernel_id
	_nodes = nodes.duplicate(true)
	_edges = edges.duplicate(true)
	_slots = slots.duplicate(true)
	if not _nodes.is_empty() and _selected.is_empty(): _selected = str(_nodes[0].get("id", ""))
	if _selected_module < 0: _feedback.set_selected("part:" + _selected)
	_update_field()
	queue_redraw()


func sync_design(installed: Array, connections: Array, lineage: Array) -> void:
	if _installed == installed and _connections == connections and _lineage == lineage: return
	if _pressed_module >= 0 and (_pressed_module >= installed.size() or str(installed[_pressed_module]).is_empty()):
		cancel_module_drag("removed")
	for index in _installed.size():
		if index>=installed.size() or str(_installed[index])!=str(installed[index]):
			_cell_growth.erase("patch:"+str(index)+":"+str(_installed[index]))
	_installed = installed.duplicate(true)
	_connections = connections.duplicate(true)
	_lineage = lineage.duplicate(true)
	if _selected_module >= 0 and (_selected_module >= installed.size() or str(installed[_selected_module]).is_empty()): select_part(_selected)
	_update_field()
	queue_redraw()


func select_part(id: String) -> void:
	_selected = id
	_selected_module = -1
	_feedback.set_selected("part:" + id)
	queue_redraw()


func set_family_texture(texture: Texture2D) -> void:
	if _family_art!=null:
		_family_art.texture=texture
		_update_field()
		queue_redraw()


func _point(index: int) -> Vector2:
	var points: Array=SHAPES.get(_kernel_id,SHAPES.stance)
	var rect:=Rect2(Vector2.ZERO,size)
	if _family_art!=null and _family_art.texture!=null:
		var source:=Vector2(_family_art.texture.get_size())
		var fit:=minf(size.x/source.x,size.y/source.y)
		rect=Rect2((size-source*fit)*.5,source*fit)
	return rect.position+(points[index%points.size()] as Vector2)*rect.size


func _module_point(index: int) -> Vector2:
	_ensure_positions()
	return _positions[clampi(index,0,4)] * size

func _core_point() -> Vector2:
	return _point(int(NUCLEUS_INDEX.get(_kernel_id,0)))


func suggested_module_position(slot: int) -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0: return Vector2(.5,.5)
	var angles: Array[float] = [-.65,.65,1.65,2.65,-2.65]
	var point := _core_point()+Vector2.from_angle(angles[clampi(slot,0,4)])*32.0
	var margin := Vector2(minf(.45,22.0/maxf(size.x,1.0)),minf(.45,22.0/maxf(size.y,1.0)))
	return (point/size.max(Vector2.ONE)).clamp(margin,Vector2.ONE-margin)


func _cell_distance(point: Vector2) -> float:
	var distance := point.distance_to(_core_point())-CORE_RADIUS
	for index in mini(_installed.size(),5):
		if str(_installed[index]).is_empty(): continue
		var patch := point.distance_to(_module_point(index))-PATCH_RADIUS
		var mix_value := clampf(.5+.5*(patch-distance)/MEMBRANE_BLEND,0.0,1.0)
		distance = lerpf(patch,distance,mix_value)-MEMBRANE_BLEND*mix_value*(1.0-mix_value)
	return distance


func _update_field() -> void:
	_bridges.clear()
	_update_neuronal_network()
	if _material == null or size.y <= 0.0 or size.x <= 0.0: return
	_material.set_shader_parameter("canvas_size",size)
	var core_point:=_core_point()/size
	_material.set_shader_parameter("core",Vector4(core_point.x,core_point.y,CORE_RADIUS,1.0))
	for index in 5:
		var attached := index < _installed.size() and not str(_installed[index]).is_empty()
		var point := _module_point(index) / size
		_material.set_shader_parameter("module_%d" % index,Vector4(point.x,point.y,PATCH_RADIUS,1.0 if attached else 0.0))
		if attached: _bridges[index] = _fusion_curve(_core_point(),_module_point(index),index)


func _draw() -> void:
	if size.x<=0 or _nodes.is_empty(): return
	var font:=get_theme_default_font()
	var ids: Dictionary={}
	for index in _nodes.size(): ids[str(_nodes[index].get("id",""))]=index
	for edge in _edges:
		if ids.has(str(edge.get("from",""))) and ids.has(str(edge.get("to",""))):
			_sketch_line(_point(int(ids[str(edge.from)])),_point(int(ids[str(edge.to)])),Color(INK,.36))
	for index in _nodes.size():
		var point:=_point(index)
		_feedback.paint(self,point,Vector2(38,32),"part:" + str(_nodes[index].get("id","")))
		var title:=str(_nodes[index].get("title",""))
		var label := point+Vector2(-56,31)
		if index == int(NUCLEUS_INDEX.get(_kernel_id,0)) and _has_nearby_patch(): label = point+Vector2(-56,-47)
		draw_string(font,label,title,HORIZONTAL_ALIGNMENT_CENTER,112,11,INK)
	for index in _installed.size():
		if str(_installed[index]).is_empty(): continue
		var point:=_module_point(index)
		_draw_fused_patch(index,point)
		_feedback.paint(self,point,Vector2(31,29),"module:" + str(index))
		var label := point+Vector2(-25,24)
		if point.distance_to(_core_point()) < 50.0: label = point+(point-_core_point()).normalized()*32.0+Vector2(-25,5)
		draw_string(font,label,"补丁%d" % (index+1),HORIZONTAL_ALIGNMENT_CENTER,50,10,INK)
	for edge in _connections:
		var from:=int(edge.get("from",-1))
		var to:=int(edge.get("to",-1))
		if from>=0 and to>=0 and from<_installed.size() and to<_installed.size(): _sketch_line(_module_point(from),_module_point(to),Color("9d503c",.45))
	for index in mini(_lineage.size(),12):
		var point:=_lineage_point(index)
		_tracking_frame(point,Vector2(12,12),Color(INK,.45))
		for parent in _lineage[index].get("parent_ids",[]):
			for other in mini(_lineage.size(),12):
				if str(_lineage[other].get("id",""))==str(parent): _sketch_line(_lineage_point(other),point,Color(INK,.24))


func _tracking_frame(point: Vector2,extent: Vector2,color: Color) -> void:
	var rect:=Rect2(point-extent*.5,extent)
	for corner in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]:
		var inward: Vector2=rect.get_center()-corner
		draw_line(corner,corner+Vector2(signf(inward.x)*7,0),color,.9,true)
		draw_line(corner,corner+Vector2(0,signf(inward.y)*7),color,.9,true)


func _has_nearby_patch() -> bool:
	for index in mini(_installed.size(),5):
		if not str(_installed[index]).is_empty() and _module_point(index).distance_to(_core_point()) < 50.0: return true
	return false


func _sketch_line(from: Vector2,to: Vector2,color: Color) -> void:
	var distance:=from.distance_to(to)
	var segments:=maxi(1,ceili(distance/10))
	for index in segments:
		var t:=float(index)/segments
		var end:=minf(1,t+5.0/maxf(distance,1))
		draw_line(from.lerp(to,t),from.lerp(to,end),color,.65,true)


func _fusion_curve(start: Vector2, end: Vector2, index: int) -> PackedVector2Array:
	var curve := PackedVector2Array()
	var bend := (end-start).orthogonal().normalized() * minf(start.distance_to(end)*.16,26.0) * (1.0 if index%2 == 0 else -1.0)
	for step in 25:
		var t := float(step)/24.0
		curve.append(start.lerp(end,t)+bend*sin(t*PI))
	return curve


func _draw_fused_patch(_index: int, _point_value: Vector2) -> void:
	pass

func _cell_record(point: Vector2,radius: float,identity: String,kernel: String,growth_key: String="") -> Dictionary:
	var key := identity if growth_key.is_empty() else growth_key
	if not _cell_growth.has(key):_cell_growth[key]=0.0
	return {"center":point,"radius":radius,"identity":identity,"kernel_id":kernel,"growth":_cell_growth[key]}

func module_graphic_config(slot: int) -> Dictionary:
	if slot<0 or slot>=_installed.size() or str(_installed[slot]).is_empty():return {}
	var id := str(_installed[slot])
	var kernel := id.trim_prefix("module_")
	if not SHAPES.has(kernel):kernel=_kernel_id
	return {"identity":id,"kernel_id":kernel}

func _update_neuronal_network() -> void:
	if _neuron_surface==null or _kernel_id.is_empty():return
	var cells: Array=[]
	var links: Array=[]
	cells.append(_cell_record(_core_point(),14.0,"core:"+_kernel_id,_kernel_id))
	for index in mini(_installed.size(),5):
		var id := str(_installed[index])
		if id.is_empty():continue
		var config := module_graphic_config(index)
		cells.append(_cell_record(_module_point(index),8.3,id,str(config.kernel_id),"patch:"+str(index)+":"+id))
		if _module_point(index).distance_to(_core_point())<90.0:
			links.append({"points":_fusion_curve(_core_point(),_module_point(index),index),"width":1.6,"growth":cells[-1].growth})
	var ids: Dictionary={}
	for index in _nodes.size():ids[str(_nodes[index].get("id",""))]=index
	for edge: Dictionary in _edges:
		if ids.has(str(edge.get("from",""))) and ids.has(str(edge.get("to",""))):
			links.append({"points":_fusion_curve(_point(ids[str(edge.from)]),_point(ids[str(edge.to)]),0),"width":2.6,"growth":cells[0].growth,"arbor":true,"identity":_kernel_id+str(edge.from)+str(edge.to)})
	for edge: Dictionary in _connections:
		var from := int(edge.get("from",-1))
		var to := int(edge.get("to",-1))
		if from>=0 and to>=0 and from<_installed.size() and to<_installed.size():
			links.append({"points":_fusion_curve(_module_point(from),_module_point(to),from),"width":.7,"growth":1.0})
	var variant_points: Dictionary={}
	for index in mini(_lineage.size(),12):
		var record: Dictionary=_lineage[index]
		var point := _lineage_point(index)
		variant_points[str(record.get("id",index))]=point
		cells.append(_cell_record(point,5.0,"variant:"+str(record.get("id",index)),str(record.get("kernel_id",_kernel_id))))
	for index in mini(_lineage.size(),12):
		var record: Dictionary=_lineage[index]
		for parent: Variant in record.get("parent_ids",[]):
			if variant_points.has(str(parent)):
				links.append({"points":_fusion_curve(variant_points[str(parent)],_lineage_point(index),index),"width":.7,"growth":_cell_growth.get("variant:"+str(record.get("id",index)),0.0)})
	_neuron_surface.set_network(cells,links)

func _lineage_point(index: int) -> Vector2:
	return Vector2(22+posmod(index,6)*31,size.y-18-(index/6)*34)

func neuron_renderer() -> Control:
	return _neuron_surface


func _gui_input(event: InputEvent) -> void:
	if not _interaction_enabled: return
	if event is InputEventMouseMotion:
		if not is_finite(event.position.x) or not is_finite(event.position.y):
			cancel_module_drag("nonfinite")
			return
		_feedback.set_hover(_hit_id(event.position))
		if _pressed_module < 0: return
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			cancel_module_drag("left_not_held")
			return
		if not _dragging and event.position.distance_to(_press_point) >= 4.0:
			_dragging = true
			_connect_from = -1
		if _dragging:
			var margin := Vector2(minf(22.0/maxf(size.x,1),.1),minf(22.0/maxf(size.y,1),.1))
			_positions[_pressed_module] = (event.position/size).clamp(margin,Vector2.ONE-margin)
			_update_field()
			queue_redraw()
		accept_event()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if not event.pressed:
		_feedback.set_pressed("")
		if _pressed_module < 0: return
		if not _dragging and event.position.distance_to(_press_point) >= 4.0:
			cancel_module_drag("release_without_motion")
			return
		var slot := _pressed_module
		_pressed_module = -1
		if _dragging:
			_drag_count += 1
			_last_drag = {"slot":slot,"position":_positions[slot],"committed":true}
			module_position_changed.emit(slot,_positions[slot])
		elif _connect_from < 0: _connect_from = slot
		elif _connect_from != slot:
			connection_requested.emit(_connect_from,slot)
			_connect_from = -1
		_dragging = false
		accept_event()
		return
	var hit := _hit_id(event.position)
	_feedback.set_hover(hit)
	_feedback.set_pressed(hit)
	if hit.begins_with("module:"):
		var slot := int(hit.trim_prefix("module:"))
		select_module(slot)
		_pressed_module = slot
		_press_point = event.position
		_drag_origin = _positions[slot]
		installed_selected.emit(slot,str(_installed[slot]))
		accept_event()
		return
	if hit.begins_with("part:"):
		select_part(hit.trim_prefix("part:"))
		part_selected.emit(_selected)
		accept_event()
		return
	for index in mini(_lineage.size(),12):
		if event.position.distance_to(_lineage_point(index))<=11:
			variant_selected.emit(str(_lineage[index].get("id","")))
			accept_event()
			return


func _can_drop_data(at_position: Vector2,data: Variant) -> bool:
	if not _interaction_enabled or not Rect2(Vector2.ZERO,size).has_point(at_position) or data is not Dictionary: return false
	var type:=str(data.get("type",""))
	return (type=="design_module" and not str(data.get("module_id","" )).is_empty()) or (type=="design_solid" and (not _solid_id(data).is_empty() or int(data.get("slot",-1))>=0)) or (type=="design_context" and not str(data.get("context_id","" )).is_empty())


func _solid_id(data: Dictionary) -> String:
	var value: Variant = data.get("solid_id","")
	return str(value) if value is String or value is StringName else ""


func _drop_data(at_position: Vector2,data: Variant) -> void:
	if not _can_drop_data(at_position,data): return
	if str(data.get("type",""))=="design_solid":
		var solid_id := _solid_id(data)
		if not solid_id.is_empty(): solid_id_drop_requested.emit(solid_id)
		else: solid_drop_requested.emit(int(data.slot))
		return
	if str(data.get("type",""))=="design_context": context_drop_requested.emit(str(data.context_id)); return
	var slot:=clampi(roundi((at_position.x/maxf(size.x,1)-.18)/.15),0,4)
	_last_drop={"at_position":at_position,"size":size,"slot":slot,"global_mouse":get_global_mouse_position()}
	module_drop_requested.emit(slot,str(data.module_id))


func inspection() -> Dictionary:
	var points := {}
	var module_points := {}
	var anatomy := {}
	for index in _installed.size():
		if not str(_installed[index]).is_empty(): module_points[index]=_module_point(index)
	for index in _nodes.size():
		var id:=str(_nodes[index].get("id",""))
		points[id]=_point(index)
		anatomy[id]="nucleus" if index==int(NUCLEUS_INDEX.get(_kernel_id,0)) else ("axon" if index==_nodes.size()-1 else "dendrite")
	return {"kernel_id":_kernel_id,"nodes":_nodes.duplicate(true),"edges":_edges.duplicate(true),
		"node_points":points,"anatomy":anatomy,"selected":_selected,"installed":_installed.duplicate(true),
		"module_points":module_points,"module_positions":_positions.duplicate(),"module_position_space":"normalized",
		"fusion_bridges":_bridges.duplicate(true),"patch_body_count":module_points.size(),
		"fusion_bridge_role":"legacy_position_reference","rendered_long_axons":0,"cell_fusion_mode":"smooth_membrane_union",
		"morphology_version":10,"neuron_renderer":"shared_procedural_neuron","neuron_surface":_neuron_surface.inspection() if _neuron_surface!=null else {},
		"core_radius":CORE_RADIUS,"patch_radius":PATCH_RADIUS,"membrane_blend":MEMBRANE_BLEND,
		"feedback":_feedback.inspection(),"selected_module":_selected_module,"interaction_enabled":_interaction_enabled,
		"dragging_slot":_pressed_module if _dragging else -1,"drag_count":_drag_count,"cancel_count":_cancel_count,"last_drag":_last_drag.duplicate(true),"tooltip":tooltip_text,
		"last_drop":_last_drop.duplicate(),
		"connections":_connections.duplicate(true),"lineage":_lineage.duplicate(true),
		"topology_signature":JSON.stringify([_kernel_id,SHAPES.get(_kernel_id,[]),_edges]),
		"metaball_shader":Metaball.resource_path,"relation_evidence":"design visualization only", "mouse_filter":mouse_filter,"tracking_style":"corner_wireframe","solid_covers":false,"edge_width":.65,"edge_dashed":true,"base_alpha":_family_art.modulate.a if _family_art!=null else 0}
