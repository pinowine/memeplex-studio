class_name DeskDendriteTree
extends Control

signal node_selected(id: String)

const INK := Color("485046")
const SketchShader = preload("res://shaders/studio/desk_sketch_base.gdshader")
const UnionShader = preload("res://shaders/studio/desk_neuron_ink.gdshader")
const NeuronGeometry=preload("res://scripts/presentation/studio/design/desk_neuron_geometry.gd")
const BlobFeedback = preload("res://scripts/presentation/studio/desk/desk_blob_feedback.gd")
const UNION_PIXEL_SCALE := 2
var _skills: Array = []
var _unlocked: Array = []
var _points: Dictionary = {}
var _paths: Dictionary = {}
var _twigs: Dictionary = {}
var _growth: Dictionary = {}
var _selected := "text"
var _rebuilds := 0
var _feedback := BlobFeedback.new()
var _interaction_enabled := true
var _growth_resets := 0
var _union_layers: Dictionary = {}
var _scaffold_stamp := -1
var _active_stamp := ""
var _union_updates := 0


class UnionPainter extends Node2D:
	var polygons: Array[PackedVector2Array] = []
	var mesh: ArrayMesh
	func _draw() -> void:
		# One opaque mesh unites branches without internal contour seams.
		if mesh!=null and mesh.get_surface_count()>0:draw_mesh(mesh,null)


func set_interaction_enabled(value: bool) -> void:
	_interaction_enabled = value
	_feedback.set_enabled(value)
	if not value: _feedback.set_pressed("")
	queue_redraw()


func select_node(id: String) -> void:
	_selected = id
	_feedback.set_selected(id)
	queue_redraw()


func _on_mouse_exited() -> void:
	_feedback.set_hover("")


func _hit_id(at: Vector2) -> String:
	for id: String in _points:
		if at.distance_to(_points[id]) <= 27.0: return id
	return ""


func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	clip_contents=true
	var pencil:=ShaderMaterial.new()
	pencil.shader=SketchShader
	material=pencil
	_make_union_layer("scaffold",false)
	_make_union_layer("active",true)
	resized.connect(_rebuild)
	mouse_exited.connect(_on_mouse_exited)
	tooltip_text = ""
	_rebuild()


func configure(skills: Array) -> void:
	if _skills==skills: return
	_skills=skills.duplicate(true)
	_rebuild()


func sync_state(unlocked: Array, selected: String = "text") -> void:
	for id: String in _growth:
		if id not in unlocked and float(_growth[id]) != 0.0:
			_growth[id] = 0.0
			_growth_resets += 1
	_unlocked = unlocked.duplicate()
	select_node(selected)
	for skill: Dictionary in _skills:
		var id := str(skill.get("id",""))
		if not _growth.has(id): _growth[id] = 0.0
		var blocked := false
		for dependency: Variant in skill.get("requires",[]):
			if str(dependency) not in _unlocked: blocked = true
		_feedback.set_disabled(id,blocked and id not in _unlocked)
	queue_redraw()


func _process(delta: float) -> void:
	var changed := _feedback.tick(delta,_points.keys())
	for skill: Dictionary in _skills:
		var id := str(skill.get("id",""))
		var reached := true
		for parent: Variant in skill.get("requires",[]):
			if float(_growth.get(str(parent),0.0)) < 1.0: reached = false
		if reached and id in _unlocked and float(_growth.get(id,0.0)) < 1.0:
			_growth[id] = move_toward(float(_growth[id]),1.0,maxf(delta,0)*.85)
			changed = true
	if changed: queue_redraw()


func _rebuild() -> void:
	_points.clear()
	_paths.clear()
	_twigs.clear()
	_rebuilds+=1
	if size.x<=0 or size.y<=0: return
	var depths: Dictionary={}
	var rows: Dictionary={}
	for skill in _skills:
		var depth:=0
		for dependency in skill.get("requires",[]): depth=maxi(depth,int(depths.get(str(dependency),0))+1)
		depths[str(skill.get("id",""))]=depth
		rows[depth]=int(rows.get(depth,0))+1
	var offsets: Dictionary={}
	var highest:=1
	for depth in depths.values(): highest=maxi(highest,int(depth))
	for skill in _skills:
		var id:=str(skill.get("id",""))
		var depth:=int(depths.get(id,0))
		var row:=int(offsets.get(depth,0))
		offsets[depth]=row+1
		var fraction:=float(row+1)/(int(rows.get(depth,1))+1)
		_points[id]=Vector2(38+depth*(maxf(80,size.x-80)/highest),size.y*(.15+.67*fraction))
	for skill in _skills:
		var id:=str(skill.get("id",""))
		var parents: Array=skill.get("requires",[]).duplicate()
		if parents.is_empty(): parents.append("")
		var curves: Array=[]
		var twigs: Array=[]
		var rng:=RandomNumberGenerator.new()
		rng.seed=id.hash()
		for parent in parents:
			var start: Vector2=_points.get(str(parent),Vector2(-18,size.y*.56))
			var end: Vector2=_points[id]
			var curve:=PackedVector2Array()
			for step in 33:
				var t:=float(step)/32
				var bend:=sin(t*PI)*Vector2((end.x-start.x)*.10,(int(id.hash()%3)-1)*23)
				curve.append(start.lerp(end,t)+bend)
			var path_index:=curves.size()
			curves.append(curve)
			for index in [7,14,21]:
				var tangent: Vector2=(curve[index+1]-curve[index]).normalized()
				var direction:=tangent.rotated(.8 if index%2==0 else -.9)
				_cache_twig(curve[index],direction,rng.randf_range(24,40),3,rng,twigs,float(index)/32,path_index)
		_paths[id]=curves
		_twigs[id]=twigs
	queue_redraw()


func _cache_twig(start: Vector2,direction: Vector2,length: float,depth: int,rng: RandomNumberGenerator,output: Array,at: float,path_index: int) -> void:
	if depth<=0: return
	var tip:=start+direction*length
	var curve:=PackedVector2Array([start,start.lerp(tip,.5)+direction.orthogonal()*rng.randf_range(-3,3),tip])
	output.append({"points":curve,"depth":depth,"anchor":at,"path_index":path_index})
	for side in [-1,1]:
		_cache_twig(tip,direction.rotated(side*rng.randf_range(.45,.76)),length*.57,depth-1,rng,output,at,path_index)


func _grown_curve(path: PackedVector2Array, growth: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if path.size() < 2 or growth <= 0.0: return points
	var progress := clampf(growth,0.0,1.0) * (path.size()-1)
	var whole := floori(progress)
	for index in whole + 1: points.append(path[index])
	if whole < path.size()-1:
		var tip := path[whole].lerp(path[whole+1],progress-whole)
		# Coalesce subpixel tips instead of creating a near-zero polygon edge.
		if tip.distance_squared_to(points[-1]) > .000001: points.append(tip)
	return points


func _tube(path: PackedVector2Array, growth: float) -> PackedVector2Array:
	var grown := _grown_curve(path,growth)
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	if grown.size() < 2: return upper
	for index in grown.size():
		# Partial tips use smooth normals from the full curve, not the tiny last edge.
		var t := minf(float(index)/(path.size()-1),growth)
		var at := t * (path.size()-1)
		var whole := floori(at)
		var next := mini(whole+1,path.size()-1)
		var first_tangent := (path[mini(whole+1,path.size()-1)]-path[maxi(whole-1,0)]).normalized()
		var next_tangent := (path[mini(next+1,path.size()-1)]-path[maxi(next-1,0)]).normalized()
		var tangent := first_tangent.lerp(next_tangent,at-whole).normalized()
		var swell := exp(-pow((t-.94)/.09,2))*9.0
		var radius := 2.5+(1-t)*1.1+swell
		upper.append(grown[index]+tangent.orthogonal()*radius)
		lower.append(grown[index]-tangent.orthogonal()*radius)
	lower.reverse()
	upper.append_array(lower)
	return upper


func _draw_tube(path: PackedVector2Array, growth: float, active: bool) -> void:
	var tube := _tube(path,growth)
	if tube.size() < 4: return
	draw_colored_polygon(tube,Color(.65,.70,.57,.18 if active else .045))
	for contour: PackedVector2Array in _tube_contours(tube,growth):
		draw_polyline(contour,Color(INK,.68 if active else .25),.85 if active else .55,true)


func _tube_contours(tube: PackedVector2Array, growth: float) -> Array[PackedVector2Array]:
	var contours: Array[PackedVector2Array] = []
	if tube.size() < 4: return contours
	var count := tube.size()/2
	var upper := tube.slice(0,count)
	var lower := tube.slice(count)
	# Node junctions share the existing body; only a growing tip needs a cap.
	if growth < 1.0: upper.append(lower[0])
	contours.append(upper)
	contours.append(lower)
	return contours


func _make_union_layer(id: String, active: bool) -> void:
	var viewport := SubViewport.new()
	viewport.name = "Union"+id.capitalize()+"Mask"
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var painter := UnionPainter.new()
	viewport.add_child(painter)
	var display := TextureRect.new()
	display.name = "Union"+id.capitalize()+"Body"
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.texture = viewport.get_texture()
	display.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	display.show_behind_parent = true
	var union_material := ShaderMaterial.new()
	union_material.shader = UnionShader
	union_material.set_shader_parameter("opacity",.84 if active else .12)
	union_material.set_shader_parameter("pixel_scale",float(UNION_PIXEL_SCALE))
	display.material = union_material
	add_child(display)
	_union_layers[id] = {"viewport":viewport,"painter":painter,"display":display}


func _disc_polygon(center: Vector2, radius: float) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for index in 32: polygon.append(center+Vector2.from_angle(float(index)*TAU/32.0)*radius)
	return polygon


func _twig_tube(path: PackedVector2Array, growth: float, radius: float) -> PackedVector2Array:
	var grown := _grown_curve(path,growth)
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	if grown.size() < 2: return upper
	for index in grown.size():
		var t := minf(float(index)/(path.size()-1),growth)
		var at := t*(path.size()-1)
		var whole := floori(at)
		var next := mini(whole+1,path.size()-1)
		var first := (path[mini(whole+1,path.size()-1)]-path[maxi(whole-1,0)]).normalized()
		var second := (path[mini(next+1,path.size()-1)]-path[maxi(next-1,0)]).normalized()
		var normal := first.lerp(second,at-whole).normalized().orthogonal()
		var width := lerpf(radius,.18,t)
		upper.append(grown[index]+normal*width)
		lower.append(grown[index]-normal*width)
	lower.reverse()
	upper.append_array(lower)
	return upper


func _union_polygons(active: bool) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for skill: Dictionary in _skills:
		var id := str(skill.get("id",""))
		var growth := float(_growth.get(id,0.0)) if active else 1.0
		var path_growth := clampf(growth/.72,0.0,1.0)
		var cell_growth := clampf((growth-.72)/.28,0.0,1.0)
		var width := 4.7 if skill.get("requires",[]).is_empty() else 2.2
		for curve: PackedVector2Array in _paths.get(id,[]):
			polygons.append_array(NeuronGeometry.stroke(curve,path_growth,width,.6))
		for twig: Dictionary in _twigs.get(id,[]):
			var level := 3-int(twig.depth)
			var windows: Array[float]=[0.0,.5,.8,1.0]
			var start := float(twig.anchor)+(1.0-float(twig.anchor))*windows[level]
			var end := float(twig.anchor)+(1.0-float(twig.anchor))*windows[level+1]
			var progress := clampf((path_growth-start)/maxf(end-start,.01),0.0,1.0) if active else 1.0
			polygons.append_array(NeuronGeometry.stroke(twig.points,progress,float(twig.depth)*.42,.10))
		if _points.has(id):
			polygons.append_array(NeuronGeometry.cell(_points[id],8.5,"skill:"+id,"relation",cell_growth))
	return polygons


func _update_union_layer(id: String, active: bool) -> void:
	if not _union_layers.has(id): return
	var layer: Dictionary = _union_layers[id]
	var viewport: SubViewport = layer.viewport
	var painter: UnionPainter = layer.painter
	var display: TextureRect = layer.display
	viewport.size = Vector2i(maxi(1,ceili(size.x*UNION_PIXEL_SCALE)),maxi(1,ceili(size.y*UNION_PIXEL_SCALE)))
	painter.scale = Vector2.ONE*UNION_PIXEL_SCALE
	display.size = size
	painter.polygons = _union_polygons(active)
	painter.mesh=NeuronGeometry.mask_mesh(painter.polygons)
	painter.queue_redraw()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_union_updates += 1


func _update_union_masks() -> void:
	if _scaffold_stamp != _rebuilds:
		_update_union_layer("scaffold",false)
		_scaffold_stamp = _rebuilds
	var stamp := str(_rebuilds)+"|"+JSON.stringify(_growth)
	if _active_stamp != stamp:
		_update_union_layer("active",true)
		_active_stamp = stamp


func union_image(active: bool = true) -> Image:
	var layer: Dictionary = _union_layers.get("active" if active else "scaffold",{})
	if layer.is_empty(): return null
	return (layer.viewport as SubViewport).get_texture().get_image()


func _draw() -> void:
	var font := get_theme_default_font()
	_update_union_masks()
	for skill: Dictionary in _skills:
		var id := str(skill.get("id",""))
		if not _points.has(id): continue
		var point: Vector2 = _points[id]
		var growth := float(_growth.get(id,0.0))
		var cell_growth := clampf((growth-.72)/.28,0.0,1.0)
		var opacity := .85 if cell_growth>0.0 else .17
		var radius := 2.8*minf(cell_growth*4.0,1.0) if cell_growth>0 else 2.8
		draw_circle(point,radius+.9,Color("e4e0cf"))
		draw_arc(point,radius,0,TAU,20,Color(INK,opacity),.7,true)
		draw_circle(point,radius*.46,Color(INK,opacity))
		_feedback.paint(self,point,Vector2(38,36),id)
		draw_string(font,point+Vector2(-45,32),DeskLocalization.text(str(skill.get("title",""))),HORIZONTAL_ALIGNMENT_CENTER,90,11,INK)


func _gui_input(event: InputEvent) -> void:
	if not _interaction_enabled: return
	if event is InputEventMouseMotion:
		_feedback.set_hover(_hit_id(event.position))
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_feedback.set_pressed("")
			return
		var id := _hit_id(event.position)
		_feedback.set_hover(id)
		_feedback.set_pressed(id)
		if not id.is_empty():
			select_node(id)
			node_selected.emit(id)
			accept_event()


func inspection() -> Dictionary:
	var dependencies: Dictionary={}
	var twig_count:=0
	for skill in _skills: dependencies[str(skill.get("id",""))]=(skill.get("requires",[]) as Array).duplicate()
	for twigs in _twigs.values(): twig_count+=twigs.size()
	return {"node_points":_points.duplicate(),"growth":_growth.duplicate(),"selected":_selected,"unlocked":_unlocked.duplicate(),
		"paths":_paths.duplicate(true),"dependencies":dependencies,"twig_count":twig_count,"recursion_depth":3,"rebuilds":_rebuilds,
		"origin":Vector2(-18,size.y*.56),"shader":SketchShader.resource_path,"uses_private_rng":true,"branch_style":"continuous_tapered_swelling_tree",
		"scaffold_paths":_paths.duplicate(true),"scaffold_continuous":true,"growth_resets":_growth_resets,
		"growth_sequence":"incoming_branch_then_soma_and_arbors","morphology_version":10,"nucleus_count":_points.size(),"body_shape":"star_soma_fine_arbors","shared_geometry":"res://scripts/presentation/studio/design/desk_neuron_geometry.gd","body_union_mode":"native_mask_union","union_shader":UnionShader.resource_path,"union_updates":_union_updates,"union_pixel_scale":UNION_PIXEL_SCALE,
		"feedback":_feedback.inspection(),"interaction_enabled":_interaction_enabled,"tooltip":tooltip_text}
