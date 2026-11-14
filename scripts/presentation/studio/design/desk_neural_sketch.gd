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

const NeuronSurface=preload("res://scripts/presentation/studio/design/desk_neuron_surface.gd")
const NeuronGeometry=preload("res://scripts/presentation/studio/design/desk_neuron_geometry.gd")
const Metaball = preload("res://shaders/studio/desk_neuron_cells.gdshader")
const BlobFeedback = preload("res://scripts/presentation/studio/desk/desk_blob_feedback.gd")
const INK := Color("485046")
const OWN_INK := Color(.18, .21, .17)
const EXTERNAL_INK := Color("a25b38")
const CORE_RADIUS := 22.0
const PATCH_RADIUS := 14.0
const MEMBRANE_BLEND := 14.0
const LAYOUT_INSET := 48.0
const SHAPES := {"stance":[Vector2(.50,.46),Vector2(.16,.08),Vector2(.84,.90)],
	"relation":[Vector2(.16,.08),Vector2(.84,.90),Vector2(.50,.46)],
	"ritual":[Vector2(.84,.90),Vector2(.50,.46),Vector2(.16,.08)],
	"boundary":[Vector2(.16,.08),Vector2(.84,.90),Vector2(.50,.46)],
	"shared_world":[Vector2(.16,.08),Vector2(.50,.46),Vector2(.84,.90)]}
const NUCLEUS_INDEX := {"stance":0,"relation":2,"ritual":1,"boundary":2,"shared_world":1}
const PATCH_ANCHORS := [Vector2(.84,.08),Vector2(.08,.50),Vector2(.92,.50),Vector2(.16,.90)]

var _kernel_id := ""
var _nodes: Array = []
var _edges: Array = []
var _slots: Dictionary = {}
var _display_slots: Dictionary = {}
var _installed: Array = []
var _connections: Array = []
var _lineage: Array = []
var _visible_lineage: Array = []
var _core_variant_id := ""
var _lineage_positions: Dictionary = {}
var _lineage_layout_stamp := ""
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
	mouse_default_cursor_shape = cursor_shape_at(get_local_mouse_position())
	queue_redraw()


func set_module_positions(positions: Array) -> void:
	if positions.size() != _installed.size(): return
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
	if _positions.size() == _installed.size(): return
	_positions.clear()
	for index in _installed.size(): _positions.append(Vector2(.18 + .60 * index / maxf(_installed.size()-1,1),.82))


func _hit_id(at: Vector2) -> String:
	for index in _installed.size():
		if not str(_installed[index]).is_empty() and at.distance_to(_module_point(index)) <= 23: return "module:" + str(index)
	for index in _nodes.size():
		if at.distance_to(_point(index)) <= 29: return "part:" + str(_nodes[index].get("id",""))
	return ""


func _on_mouse_exited() -> void:
	_feedback.set_hover("")
	mouse_default_cursor_shape = CURSOR_ARROW


func cursor_shape_at(point: Vector2) -> int:
	if not _interaction_enabled: return CURSOR_ARROW
	if _pressed_module >= 0 or not _hit_id(point).is_empty(): return CURSOR_POINTING_HAND
	for index in _visible_lineage.size():
		if point.distance_to(_lineage_point(index)) <= 18: return CURSOR_POINTING_HAND
	return CURSOR_ARROW


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
	pencil.shader=preload("res://shaders/studio/desk_sketch_base.gdshader")
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready(): queue_redraw()

func set_display_slots(slots: Dictionary) -> void:
	_display_slots = slots.duplicate(true)
	queue_redraw()

func configure(kernel_id: String, nodes: Array, edges: Array, slots: Dictionary) -> void:
	_kernel_id = kernel_id
	_nodes = nodes.duplicate(true)
	_edges = edges.duplicate(true)
	_slots = slots.duplicate(true)
	_display_slots = slots.duplicate(true)
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
	_rebuild_visible_lineage()
	if _selected_module >= 0 and (_selected_module >= installed.size() or str(installed[_selected_module]).is_empty()): select_part(_selected)
	_update_field()
	queue_redraw()


func set_core_variant(id: String) -> void:
	if _core_variant_id == id: return
	_core_variant_id = id
	_rebuild_visible_lineage()
	_update_field()
	queue_redraw()

func _core_lineage_id() -> String:
	for record: Dictionary in _lineage:
		if str(record.get("id", "")) == _core_variant_id and str(record.get("kernel_id", "")) == _kernel_id and str(record.get("creator", "")) == "player":
			return _core_variant_id
	return ""

func _rebuild_visible_lineage() -> void:
	_visible_lineage.clear()
	_lineage_layout_stamp = ""
	var core_id := _core_lineage_id()
	var by_id := {}
	for record: Dictionary in _lineage: by_id[str(record.id)] = record
	var seen := {}
	var pending: Array[String] = []
	if not core_id.is_empty():
		seen[core_id] = true
		pending.append(core_id)
	var cursor := 0
	# Breadth-first ancestry keeps each visible relative connected through a recorded edge.
	while cursor < pending.size() and _visible_lineage.size() < 12:
		var id := pending[cursor]
		cursor += 1
		var parents: Array = by_id[id].get("parent_ids", [])
		for record: Dictionary in _lineage:
			var other := str(record.id)
			if seen.has(other): continue
			if id not in record.get("parent_ids", []) and other not in parents: continue
			seen[other] = true
			pending.append(other)
			_visible_lineage.append(record)
			if _visible_lineage.size() == 12: break
	# The specimen contains only its recorded relatives; independent expressions remain in the ledger.
	_layout_attached_lineage()

func _lineage_ink(record: Dictionary) -> Color:
	return EXTERNAL_INK if str(record.get("creator", "player")) != "player" else OWN_INK


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


func _layout_bounds() -> Rect2:
	return Rect2(Vector2.ONE*LAYOUT_INSET,(size-Vector2.ONE*LAYOUT_INSET*2.0).max(Vector2.ONE))


func _point(index: int) -> Vector2:
	var points: Array=SHAPES.get(_kernel_id,SHAPES.stance)
	# The paper owns the layout; the hidden specimen texture has a different aspect ratio.
	var rect := _layout_bounds()
	return rect.position+(points[index%points.size()] as Vector2)*rect.size


func _module_point(index: int) -> Vector2:
	_ensure_positions()
	return _positions[index] * size

func _core_point() -> Vector2:
	return _point(int(NUCLEUS_INDEX.get(_kernel_id,0)))


func suggested_module_position(slot: int) -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0: return Vector2(.5,.5)
	var rect := _layout_bounds()
	return (rect.position+PATCH_ANCHORS[slot]*rect.size)/size


func _label_rect(point: Vector2, width: float, distance: float) -> Rect2:
	var extent := Vector2(width,20)
	var origin := point+Vector2(-width*.5,distance-12)
	return Rect2(origin.clamp(Vector2(8,8),(size-extent-Vector2(8,24)).max(Vector2(8,8))),extent)


func _part_label_rect(index: int) -> Rect2:
	var point := _point(index)
	# The gap below the core stays clear of the four default patch branches.
	var distance := 96 if index==int(NUCLEUS_INDEX.get(_kernel_id,0)) else (-56 if point.y<_core_point().y else 64)
	return _label_rect(point,112,distance)


func _module_label_rect(index: int) -> Rect2:
	var point := _module_point(index)
	return _label_rect(point,64,-56 if point.y<_core_point().y else 64)


func _update_field() -> void:
	_bridges.clear()
	_update_neuronal_network()
	if _material == null or size.y <= 0.0 or size.x <= 0.0: return
	_material.set_shader_parameter("canvas_size",size)
	var core_point:=_core_point()/size
	_material.set_shader_parameter("core",Vector4(core_point.x,core_point.y,CORE_RADIUS,1.0))
	for index in 5:
		var attached := index < _installed.size() and not str(_installed[index]).is_empty()
		var point := _module_point(index) / size if attached else Vector2.ZERO
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
		var title:=DeskLocalization.text(str(_nodes[index].get("title","")))
		var label := _part_label_rect(index)
		draw_string(font,label.position+Vector2(0,12),title,HORIZONTAL_ALIGNMENT_CENTER,label.size.x,11,INK)
	for index in _installed.size():
		if str(_installed[index]).is_empty(): continue
		var point:=_module_point(index)
		_draw_fused_patch(index,point)
		_feedback.paint(self,point,Vector2(31,29),"module:" + str(index))
		var label := _module_label_rect(index)
		draw_string(font,label.position+Vector2(0,12),DeskLocalization.format_text("LOC_PATCH_D_3EC77C1A", (index+1)),HORIZONTAL_ALIGNMENT_CENTER,label.size.x,10,INK)
	for edge in _connections:
		var from:=int(edge.get("from",-1))
		var to:=int(edge.get("to",-1))
		if from>=0 and to>=0 and from<_installed.size() and to<_installed.size(): _sketch_line(_module_point(from),_module_point(to),Color(BlobFeedback.ACTIVE,.45))
	for index in _visible_lineage.size():
		var point:=_lineage_point(index)
		_tracking_frame(point,Vector2(12,12),Color(_lineage_ink(_visible_lineage[index]),.65))
	if not _visible_lineage.is_empty():
		draw_circle(Vector2(10,size.y-10),3,OWN_INK)
		draw_string(font,Vector2(18,size.y-6),DeskLocalization.text("LOC_YOUR_OWN_EXPRESSION_0A35E8E2"),HORIZONTAL_ALIGNMENT_LEFT,-1,11,INK)
		var marker_x := minf(size.x*.48,150.0)
		draw_circle(Vector2(marker_x,size.y-10),3,EXTERNAL_INK)
		draw_string(font,Vector2(marker_x+8,size.y-6),DeskLocalization.text("LOC_EDIT_EXTERNAL_EXPRESSION"),HORIZONTAL_ALIGNMENT_LEFT,-1,11,EXTERNAL_INK)


func _tracking_frame(point: Vector2,extent: Vector2,color: Color) -> void:
	var rect:=Rect2(point-extent*.5,extent)
	for corner in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]:
		var inward: Vector2=rect.get_center()-corner
		draw_line(corner,corner+Vector2(signf(inward.x)*7,0),color,.9,true)
		draw_line(corner,corner+Vector2(0,signf(inward.y)*7),color,.9,true)


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
	return {"center":point,"radius":radius,"identity":identity,"kernel_id":kernel,"growth":_cell_growth[key],"ink":OWN_INK}

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
	for index in _nodes.size():
		if index == int(NUCLEUS_INDEX.get(_kernel_id,0)): continue
		cells.append(_cell_record(_point(index),8.3,"part:"+_kernel_id+":"+str(_nodes[index].get("id","")),_kernel_id))
	for index in _installed.size():
		var id := str(_installed[index])
		if id.is_empty():continue
		var config := module_graphic_config(index)
		cells.append(_cell_record(_module_point(index),8.3,id,str(config.kernel_id),"patch:"+str(index)+":"+id))
		links.append({"points":_fusion_curve(_core_point(),_module_point(index),index),"width":1.6,"growth":cells[-1].growth,"role":"patch","slot":index})
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
	_layout_attached_lineage()
	var variant_points: Dictionary={}
	var linked_records := _visible_lineage.duplicate()
	var core_id := _core_lineage_id()
	if not core_id.is_empty():
		variant_points[core_id] = _core_point()
		for record: Dictionary in _lineage:
			if str(record.id) == core_id: linked_records.append(record)
	for index in _visible_lineage.size():
		var record: Dictionary=_visible_lineage[index]
		var id := str(record.id)
		var point := _lineage_point(index)
		variant_points[id]=point
		var cell := _cell_record(point,8.3,"variant:"+id,str(record.get("kernel_id",_kernel_id)))
		cell.ink = _lineage_ink(record)
		cell.external = str(record.get("creator", "player")) != "player"
		cells.append(cell)
	for record: Dictionary in linked_records:
		var id := str(record.id)
		for parent: Variant in record.get("parent_ids",[]):
			if variant_points.has(str(parent)):
				var growth: float = _cell_growth.get("core:"+_kernel_id if id == core_id else "variant:"+id,0.0)
				links.append({"points":_fusion_curve(variant_points[str(parent)],variant_points[id],links.size()),"width":1.05,"growth":growth,"ink":_lineage_ink(record),"role":"lineage","from_variant":str(parent),"to_variant":id})
	_neuron_surface.set_network(cells,links)

func _lineage_point(index: int) -> Vector2:
	return _lineage_positions.get(str(_visible_lineage[index].id), _core_point())

func _layout_attached_lineage() -> void:
	var stamp := str(size) + str(_core_point()) + _kernel_id + JSON.stringify([_installed, _positions])
	if stamp == _lineage_layout_stamp: return
	_lineage_layout_stamp = stamp
	_lineage_positions.clear()
	if _visible_lineage.is_empty(): return
	var core_id := _core_lineage_id()
	var occupied: Array[Vector2] = []
	for index in _nodes.size(): occupied.append(_point(index))
	for index in _installed.size():
		if not str(_installed[index]).is_empty(): occupied.append(_module_point(index))
	var labels: Array[Rect2] = []
	for index in _nodes.size():
		labels.append(_part_label_rect(index).grow(24))
	for index in _installed.size():
		if str(_installed[index]).is_empty(): continue
		labels.append(_module_label_rect(index).grow(24))
	var bounds := _layout_bounds()
	for index in _visible_lineage.size():
		var record: Dictionary = _visible_lineage[index]
		var anchor := _core_point()
		for parent: Variant in record.get("parent_ids",[]):
			if str(parent) == core_id: break
			if _lineage_positions.has(str(parent)):
				anchor = _lineage_positions[str(parent)]
				break
		var best := anchor
		var best_score := INF
		for radius: float in [64.0,96.0,128.0,192.0,256.0]:
			for direction in 24:
				var angle := -PI * .5 + direction * TAU / 24.0
				var candidate := anchor + Vector2.from_angle(angle) * radius
				if not bounds.has_point(candidate): continue
				var score := radius + candidate.distance_to(_core_point()) * .65
				for point: Vector2 in occupied:
					score += maxf(0,96.0-candidate.distance_to(point)) * 100.0
				for label: Rect2 in labels:
					if label.has_point(candidate): score += 10000.0
				if score < best_score:
					best = candidate
					best_score = score
		_lineage_positions[str(record.id)] = best
		occupied.append(best)

func neuron_renderer() -> Control:
	return _neuron_surface


func _gui_input(event: InputEvent) -> void:
	if not _interaction_enabled: return
	if event is InputEventMouseMotion:
		if not is_finite(event.position.x) or not is_finite(event.position.y):
			cancel_module_drag("nonfinite")
			return
		_feedback.set_hover(_hit_id(event.position))
		mouse_default_cursor_shape = cursor_shape_at(event.position)
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
	for index in _visible_lineage.size():
		if event.position.distance_to(_lineage_point(index))<=18:
			variant_selected.emit(str(_visible_lineage[index].get("id","")))
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
	var slot:=clampi(roundi((at_position.x/maxf(size.x,1)-.18)/.60*(_installed.size()-1)),0,_installed.size()-1)
	_last_drop={"at_position":at_position,"size":size,"slot":slot,"global_mouse":get_global_mouse_position()}
	module_drop_requested.emit(slot,str(data.module_id))


func inspection() -> Dictionary:
	var points := {}
	var module_points := {}
	var node_label_rects := {}
	var module_label_rects := {}
	var anatomy := {}
	for index in _installed.size():
		if not str(_installed[index]).is_empty():
			module_points[index]=_module_point(index)
			module_label_rects[index]=_module_label_rect(index)
	for index in _nodes.size():
		var id:=str(_nodes[index].get("id",""))
		points[id]=_point(index)
		node_label_rects[id]=_part_label_rect(index)
		anatomy[id]="nucleus" if index==int(NUCLEUS_INDEX.get(_kernel_id,0)) else ("axon" if index==_nodes.size()-1 else "dendrite")
	return {"kernel_id":_kernel_id,"nodes":_nodes.duplicate(true),"edges":_edges.duplicate(true),"source_slots":_slots.duplicate(true),"display_slots":_display_slots.duplicate(true),
		"node_points":points,"node_label_rects":node_label_rects,"module_label_rects":module_label_rects,"layout_bounds":_layout_bounds(),"anatomy":anatomy,"selected":_selected,"installed":_installed.duplicate(true),
		"module_points":module_points,"module_positions":_positions.duplicate(),"module_position_space":"normalized",
		"fusion_bridges":_bridges.duplicate(true),"patch_body_count":module_points.size(),
		"fusion_bridge_role":"position_reference","rendered_long_axons":0,"cell_fusion_mode":"smooth_membrane_union",
		"morphology_version":11,"neuron_renderer":"shared_procedural_neuron","neuron_surface":_neuron_surface.inspection() if _neuron_surface!=null else {},
		"core_radius":CORE_RADIUS,"patch_radius":PATCH_RADIUS,"membrane_blend":MEMBRANE_BLEND,
		"feedback":_feedback.inspection(),"selected_module":_selected_module,"interaction_enabled":_interaction_enabled,
		"dragging_slot":_pressed_module if _dragging else -1,"drag_count":_drag_count,"cancel_count":_cancel_count,"last_drag":_last_drag.duplicate(true),"tooltip":tooltip_text,
		"last_drop":_last_drop.duplicate(),
		"connections":_connections.duplicate(true),"lineage":_lineage.duplicate(true),"visible_lineage":_visible_lineage.duplicate(true),"core_variant_id":_core_lineage_id(),"lineage_relation_source":"recorded parent_ids","lineage_layout":"attached_parent_branches","lineage_positions":_lineage_positions.duplicate(),"hidden_lineage_count":_lineage.size()-_visible_lineage.size()-(0 if _core_lineage_id().is_empty() else 1),
		"topology_signature":JSON.stringify([_kernel_id,SHAPES.get(_kernel_id,[]),_edges]),
		"metaball_shader":Metaball.resource_path,"relation_evidence":"design visualization only", "mouse_filter":mouse_filter,"tracking_style":"corner_wireframe","solid_covers":false,"edge_width":.65,"edge_dashed":true,"base_alpha":_family_art.modulate.a if _family_art!=null else 0}
