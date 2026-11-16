class_name DeskDendriteTree
extends Control

signal node_selected(id: String)

const INK := Color("485046")
const SketchShader = preload("res://shaders/studio/desk_sketch_base.gdshader")
const UnionShader = preload("res://shaders/studio/desk_neuron_ink.gdshader")
const NeuronGeometry=preload("res://scripts/presentation/studio/design/desk_neuron_geometry.gd")
const BlobFeedback = preload("res://scripts/presentation/studio/desk/desk_blob_feedback.gd")
const TextLayout = preload("res://scripts/presentation/studio/context/desk_context_resource_graphic.gd")
const LabelFont = preload("res://assets/image/fonts/body_medium_font.tres")
const SelectedFont = preload("res://assets/image/fonts/body_bold_font.tres")
const ACCENT := Color("41675f")
const UNION_PIXEL_SCALE := 2
const NODE_ROW_SPACING := 110.0
const NODE_TOP_MARGIN := 36.0
const NODE_BOTTOM_MARGIN := 84.0
const NODE_HIT_RADIUS := 18.0
var _skills: Array = []
var _unlocked: Array = []
var _points: Dictionary = {}
var _label_layouts: Dictionary = {}
var _hit_rects: Dictionary = {}
var _paths: Dictionary = {}
var _twigs: Dictionary = {}
var _growth: Dictionary = {}
var _selected := "text"
var _rebuilds := 0
var _feedback := BlobFeedback.new()
var _interaction_enabled := true
var _research_ready := true
var _vertical_layout := false
var _label_width := 144.0
var _edge_records: Array[Dictionary] = []
var _layout_depths: Dictionary = {}
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
	mouse_default_cursor_shape = cursor_shape_at(get_local_mouse_position())
	queue_redraw()


func select_node(id: String) -> void:
	_selected = id
	_feedback.set_selected(id)
	queue_redraw()


func _on_mouse_exited() -> void:
	_feedback.set_hover("")
	mouse_default_cursor_shape = CURSOR_ARROW


func cursor_shape_at(point: Vector2) -> int:
	if _hit_id(point).is_empty(): return CURSOR_ARROW
	return CURSOR_POINTING_HAND if _interaction_enabled else CURSOR_FORBIDDEN


func _hit_id(at: Vector2) -> String:
	for id: String in _points:
		if at.distance_to(_points[id]) <= NODE_HIT_RADIUS: return id
	for id: String in _hit_rects:
		if (_hit_rects[id] as Rect2).has_point(at): return id
	return ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_labels()
		queue_redraw()


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


func _dependencies(skill: Dictionary) -> Array:
	return skill.get("requires", []) + skill.get("requires_any", [])


func _requirements_met(skill: Dictionary, unlocked: Array) -> bool:
	for dependency: String in skill.get("requires", []):
		if dependency not in unlocked: return false
	var alternatives: Array = skill.get("requires_any", [])
	if alternatives.is_empty(): return true
	for dependency: String in alternatives:
		if dependency in unlocked: return true
	return false


func _structure() -> Dictionary:
	var positions := {}
	var depths := {}
	var highest := 0
	for skill: Dictionary in _skills:
		var id := str(skill.id)
		var depth := 0
		for parent: String in _dependencies(skill): depth = maxi(depth, int(depths.get(parent, 0)) + 1)
		depths[id] = depth
		highest = maxi(highest, depth)
		var column := 1.5
		match str(skill.get("route", "common")):
			"accessibility": column = 0.0 if id in ["machine_translation", "multilingual_typesetting"] else (1.0 if id in ["image", "alternative_text"] else .5)
			"open_source": column = 2.0
			"community": column = 3.0
		positions[id] = Vector2(column, depth)
	return {"positions":positions, "highest":highest, "depths":depths}


func content_minimum_height() -> float:
	return NODE_TOP_MARGIN + NODE_BOTTOM_MARGIN + float(_structure().highest) * NODE_ROW_SPACING


func node_rect(id: String) -> Rect2:
	return _hit_rects.get(id, Rect2())


func sync_state(unlocked: Array, selected: String = "text", research_ready: bool = true) -> void:
	_research_ready = research_ready
	for id: String in _growth:
		if id not in unlocked and float(_growth[id]) != 0.0:
			_growth[id] = 0.0
			_growth_resets += 1
	_unlocked = unlocked.duplicate()
	select_node(selected)
	for skill: Dictionary in _skills:
		var id := str(skill.get("id",""))
		if not _growth.has(id): _growth[id] = 0.0
		var blocked := _node_status(skill) == "locked"
		_feedback.set_disabled(id, blocked)
	queue_redraw()


func _process(delta: float) -> void:
	var changed := _feedback.tick(delta,_points.keys())
	for skill: Dictionary in _skills:
		var id := str(skill.get("id",""))
		var reached := true
		for parent: Variant in skill.get("requires", []):
			if float(_growth.get(str(parent), 0.0)) < 1.0: reached = false
		var alternatives: Array = skill.get("requires_any", [])
		if not alternatives.is_empty():
			var any_reached := false
			for parent: Variant in alternatives:
				if float(_growth.get(str(parent), 0.0)) >= 1.0: any_reached = true
			reached = reached and any_reached
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
	var structure := _structure()
	_layout_depths = structure.depths
	_vertical_layout = true
	_edge_records.clear()
	var lane_width := (size.x - 24.0) / 4.0
	_label_width = maxf(40, lane_width - 44.0)
	for skill: Dictionary in _skills:
		var id := str(skill.id)
		var slot: Vector2 = structure.positions[id]
		_points[id] = Vector2(12.0 + lane_width * slot.x + 22.0, NODE_TOP_MARGIN + slot.y * NODE_ROW_SPACING)
	for skill: Dictionary in _skills:
		var id := str(skill.id)
		var parents: Array = _dependencies(skill)
		var curves: Array = []
		var twigs: Array = []
		var point: Vector2 = _points[id]
		if parents.is_empty(): curves.append(PackedVector2Array([Vector2(point.x, -18), point + Vector2(0, -9)]))
		for parent: String in parents:
			var source: Vector2 = _points[parent]
			var start := source + Vector2(0, 9)
			var end := point + Vector2(0, -9)
			var distance := maxf(24, (end.y - start.y) * .45)
			var control_a := start + Vector2(0, distance)
			var control_b := end - Vector2(0, distance)
			var curve := PackedVector2Array()
			for step in 33:
				var t := float(step) / 32.0
				var u := 1.0 - t
				curve.append(start * u * u * u + control_a * 3.0 * u * u * t + control_b * 3.0 * u * t * t + end * t * t * t)
			curves.append(curve)
			_edge_records.append({"source":parent, "target":id, "points":curve, "alternative":parent in skill.get("requires_any", []), "connection_style":"vertical_bezier"})
		var rng := RandomNumberGenerator.new()
		rng.seed = id.hash()
		for direction: Vector2 in [Vector2(-1, 0), Vector2(-.6, -.8), Vector2(.5, -.866), Vector2(1, 0)]:
			_cache_twig(point + direction * 8.5, direction, rng.randf_range(9, 13), 1, rng, twigs, .4, 0)
		_paths[id] = curves
		_twigs[id] = twigs
	_refresh_labels()
	queue_redraw()


func _refresh_labels() -> void:
	_label_layouts.clear()
	_hit_rects.clear()
	var width := _label_width
	for skill: Dictionary in _skills:
		var id := str(skill.get("id", ""))
		if not _points.has(id): continue
		var point: Vector2 = _points[id]
		var area := Rect2(point + Vector2(22, -31), Vector2(width, 62))
		var label := TextLayout.fit_text(SelectedFont, DeskLocalization.text(str(skill.get("title", ""))), area, 15, 13, 3)
		var glyph_rect := Rect2()
		for line: Dictionary in label.lines:
			glyph_rect = line.rect if not glyph_rect.has_area() else glyph_rect.merge(line.rect)
		label.glyph_rect = glyph_rect
		_label_layouts[id] = label
		_hit_rects[id] = Rect2(point - Vector2.ONE * NODE_HIT_RADIUS, Vector2.ONE * NODE_HIT_RADIUS * 2.0).merge(area).grow(2)


func _node_status(skill: Dictionary) -> String:
	var id := str(skill.get("id", ""))
	if id in _unlocked: return "unlocked"
	if id != "text" and not _research_ready: return "locked"
	return "available" if _requirements_met(skill, _unlocked) else "locked"


func _cache_twig(start: Vector2,direction: Vector2,length: float,depth: int,rng: RandomNumberGenerator,output: Array,at: float,path_index: int) -> void:
	if depth<=0: return
	var tip:=start+direction*length
	var curve:=PackedVector2Array([start,start.lerp(tip,.5)+direction.orthogonal()*rng.randf_range(-3,3),tip])
	output.append({"points":curve,"depth":depth,"anchor":at,"path_index":path_index})
	for side in [-1,1]:
		_cache_twig(tip,direction.rotated(side*rng.randf_range(.45,.76)),length*.57,depth-1,rng,output,at,path_index)


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


func _dashed_strokes(curve: PackedVector2Array, progress: float, width: float) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var total := 0.0
	for index in range(1, curve.size()): total += curve[index - 1].distance_to(curve[index])
	var remaining := total * progress
	for index in range(1, curve.size()):
		var start := curve[index - 1]
		var delta := curve[index] - start
		var length := delta.length()
		var visible := minf(length, maxf(0, remaining))
		var offset := 0.0
		while offset < visible:
			var end := minf(offset + 6.0, visible)
			result.append_array(NeuronGeometry.stroke(PackedVector2Array([start + delta * (offset / length), start + delta * (end / length)]), 1.0, width, .6))
			offset += 11.0
		remaining -= length
	return result


func _union_polygons(active: bool) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for skill: Dictionary in _skills:
		var id := str(skill.get("id",""))
		var growth := float(_growth.get(id,0.0)) if active else 1.0
		var path_growth := clampf(growth/.72,0.0,1.0)
		var cell_growth := clampf((growth-.72)/.28,0.0,1.0)
		var width := 2.4 if _dependencies(skill).is_empty() else 1.5
		var curves: Array = _paths.get(id, [])
		var parents := _dependencies(skill)
		for index in curves.size():
			var curve: PackedVector2Array = curves[index]
			if index < parents.size() and parents[index] in skill.get("requires_any", []):
				polygons.append_array(_dashed_strokes(curve, path_growth, width))
			else: polygons.append_array(NeuronGeometry.stroke(curve, path_growth, width, .6))
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
		var selected := id == _selected
		var status := _node_status(skill)
		var color := ACCENT if selected else Color(INK, .60 if status == "locked" else 1.0)
		var font: Font = SelectedFont if selected else LabelFont
		var layout: Dictionary = _label_layouts.get(id, {})
		for line: Dictionary in layout.get("lines", []):
			draw_string(font, line.baseline, line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(line.font_size), color)



func _gui_input(event: InputEvent) -> void:
	if not _interaction_enabled: return
	if event is InputEventMouseMotion:
		_feedback.set_hover(_hit_id(event.position))
		mouse_default_cursor_shape = cursor_shape_at(event.position)
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
	var label_rects := {}
	for id: String in _label_layouts: label_rects[id] = _label_layouts[id].glyph_rect
	var dependencies: Dictionary={}
	var states := {}
	var twig_count:=0
	for skill in _skills:
		dependencies[str(skill.get("id",""))] = {"all":skill.get("requires", []).duplicate(), "any":skill.get("requires_any", []).duplicate()}
		states[str(skill.get("id", ""))] = _node_status(skill)
	for twigs in _twigs.values(): twig_count+=twigs.size()
	return {"layout_axis":"vertical" if _vertical_layout else "horizontal","research_ready":_research_ready,"node_points":_points.duplicate(),"growth":_growth.duplicate(),"selected":_selected,"unlocked":_unlocked.duplicate(),
		"label_rects":label_rects,"node_labels":_label_layouts.duplicate(true),"node_hit_rects":_hit_rects.duplicate(),"node_states":states,"selected_label_weight":700,"label_hit_enabled":true,
		"paths":_paths.duplicate(true),"edge_records":_edge_records.duplicate(true),"dependency_depths":_layout_depths.duplicate(),"decorative_twigs":_twigs.duplicate(true),"selected_label_underline":false,"node_status_symbols":false,"alternative_edge_style":"dashed","dependencies":dependencies,"twig_count":twig_count,"recursion_depth":1,"rebuilds":_rebuilds,
		"origin":Vector2(size.x * .5, -18) if _vertical_layout else Vector2(-18,size.y*.56),"shader":SketchShader.resource_path,"uses_private_rng":true,"branch_style":"continuous_tapered_swelling_tree",
		"scaffold_paths":_paths.duplicate(true),"scaffold_continuous":true,"growth_resets":_growth_resets,
		"growth_sequence":"incoming_branch_then_soma_and_arbors","morphology_version":10,"nucleus_count":_points.size(),"body_shape":"star_soma_fine_arbors","shared_geometry":"res://scripts/presentation/studio/design/desk_neuron_geometry.gd","body_union_mode":"native_mask_union","union_shader":UnionShader.resource_path,"union_updates":_union_updates,"union_pixel_scale":UNION_PIXEL_SCALE,
		"feedback":_feedback.inspection(),"interaction_enabled":_interaction_enabled,"tooltip":tooltip_text}
