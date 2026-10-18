extends Control
class_name DeskSheetStack

signal switch_started(id: String)
signal switch_completed(id: String)

const ShadowObject := preload("res://scripts/demo/desk_object_shadow.gd")
const FRONT_LAYER := 26
const BACK_LAYER := 25
const BACK_OFFSET := Vector2(-24.0, 9.0)
const SHEET_IDS := ["map", "edit", "cultivate", "spread"]

class PaperMask extends TextureRect:
	var alpha_image: Image
	func _has_point(point: Vector2) -> bool:
		if not Rect2(Vector2.ZERO, size).has_point(point): return false
		if alpha_image == null or alpha_image.is_empty(): return false
		var pixel := Vector2i(point / size * Vector2(alpha_image.get_size()))
		return alpha_image.get_pixelv(pixel).a > 0.02

class WaterInk extends Node2D:
	var terrain: Node2D
	func _draw() -> void:
		if terrain == null or terrain.river_mesh == null: return
		draw_mesh(terrain.river_mesh, null, Transform2D.IDENTITY, terrain.settings.river_color)
		for mesh in terrain.lake_meshes:
			draw_mesh(mesh, null, Transform2D.IDENTITY, terrain.settings.lake_color)

class WaterComposite extends Node2D:
	var image: Texture2D
	var map_size := Vector2.ZERO
	var view := Transform2D.IDENTITY
	var opacity := 0.0
	func _draw() -> void:
		if image == null or not map_size.is_finite() or not map_size.x > 0.0: return
		draw_set_transform_matrix(view.affine_inverse())
		draw_texture_rect(image, Rect2(Vector2.ZERO, map_size), false, Color(1, 1, 1, opacity))

class NoteIcon extends Control:
	var kind := "map"
	func _draw() -> void:
		var ink := Color("343b32")
		var center := size * 0.5
		if kind == "map":
			draw_arc(center, 9.0, 0.0, TAU, 32, ink, 1.4, true)
			var meridian := PackedVector2Array()
			for index in 33:
				var angle := float(index) * TAU / 32.0
				meridian.append(center + Vector2(sin(angle) * 4.0, cos(angle) * 9.0))
			draw_polyline(meridian, ink, 1.2, true)
			draw_line(center + Vector2(-9.0, 0.0), center + Vector2(9.0, 0.0), ink, 1.2, true)
		else:
			var pencil := PackedVector2Array([center + Vector2(-7, 7), center + Vector2(3, -7), center + Vector2(7, -4), center + Vector2(-3, 10), center + Vector2(-7, 7)])
			draw_polyline(pencil, ink, 1.5, true)
			draw_line(center + Vector2(1, -4), center + Vector2(5, -1), ink, 1.2, true)
			draw_line(center + Vector2(-6, 7), center + Vector2(-5, 9), ink, 2.0, true)

var _sheets: Dictionary = {}
var _layers: Dictionary = {}
var _tabs: Dictionary = {}
var _masks: Dictionary = {}
var _shadows: Dictionary = {}
var _offsets := {"map":Vector2.ZERO, "edit":Vector2.ZERO, "cultivate":Vector2.ZERO, "spread":Vector2.ZERO}
var _order: Array[String] = ["spread", "cultivate", "map", "edit"]
var _contents: Dictionary = {}
var _settled: Dictionary = {}
var _area := Rect2()
var _active := "edit"
var _switching := false
var _switch_target := "edit"
var _tween: Tween
var _map_input: Control
var _map_finish: Control
var _spread: Control
var _workbench: Control
var _paper: Texture2D
var _papers: Dictionary = {}
var _paper_images: Dictionary = {}
var _body_uv: Dictionary = {}
var _captured_themes: Dictionary = {}
var _owners: Dictionary = {}
var _guard_layer: CanvasLayer
var _guard: Control
var _saved_map_filter := Control.MOUSE_FILTER_STOP
var _finish_copy: BackBufferCopy
var _water_viewport: SubViewport
var _water_ink: WaterInk
var _water_composite: WaterComposite
var _water_terrain: Node2D
var _water_source: CanvasGroup
var _water_signature: Array = []
var _water_refreshes := 0

func _ready() -> void:
	process_priority = 25
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func configure(map_input: Control, map_finish: Control, spread: Control, workbench: Control, textures: Dictionary) -> bool:
	if not _sheets.is_empty() or not is_instance_valid(map_input) or not is_instance_valid(map_finish) or not is_instance_valid(spread) or not is_instance_valid(workbench):
		return false
	_paper = textures.get("paper", textures.get("landscape_paper")) as Texture2D
	var map_paper := textures.get("map_paper") as Texture2D
	var design_paper := textures.get("design_paper") as Texture2D
	if map_paper == null: map_paper = _paper
	if design_paper == null: design_paper = _paper
	if map_paper == null or design_paper == null:
		return false
	_paper = map_paper
	_papers = {"map":map_paper}
	for id in ["edit", "cultivate", "spread"]:
		_papers[id] = textures.get(id + "_paper", design_paper) as Texture2D
	for id in _papers:
		_paper_images[id] = (_papers[id] as Texture2D).get_image()
		_body_uv[id] = _opaque_body_uv(_paper_images[id])
		if not (_body_uv[id] as Rect2).has_area():
			push_error("Paper has no opaque content body: " + id)
			return false
	var map_owner: Node = map_input.owner if map_input.owner != null else map_input.get_parent()
	var design_owner: Node = workbench.owner if workbench.owner != null else workbench.get_parent()
	if not map_owner.is_ancestor_of(map_finish) or (spread.owner != null and spread.owner != map_owner and not spread.owner.is_ancestor_of(map_owner)):
		return false
	_map_input = map_input
	_map_finish = map_finish
	_spread = spread
	_workbench = workbench
	_workbench.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_owners = {"map_input":map_input.owner,"map_finish":map_finish.owner,"spread":spread.owner,"workbench":workbench.owner}
	_captured_themes = {"map":_inherited_theme(map_input)}
	for id in ["edit", "cultivate", "spread"]: _captured_themes[id] = _inherited_theme(workbench)
	_make_sheet("map", map_owner, textures)
	for id in ["edit", "cultivate", "spread"]: _make_sheet(id, design_owner, textures)
	_reparent_content(_map_input, _masks.map, 10)
	_reparent_content(_spread, _masks.map, 30)
	# Mount the three original page controls; the legacy form stays with its owner.
	var editor := workbench.get_node("DesignWorkbench")
	for id in ["edit", "cultivate", "spread"]:
		var host := Control.new()
		host.name = "Content"
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_masks[id].add_child(host)
		_contents[id] = host
		var page: Control = editor.sheet_pages()[id]
		var ownership := _capture_owners(page)
		editor.mount_sheet(id, host)
		# Moving an ownerless runtime page clears scene-owned unique descendants.
		page.owner = design_owner
		for node in ownership:
			var original_owner: Node = ownership[node]
			if original_owner != null and original_owner.is_ancestor_of(node): node.owner = original_owner
		_same_clip_depth(host)
	_reparent_finish()
	_isolate_water_group()
	_map_input.clip_contents = false
	var sea := _map_input.get_node_or_null("World/Sea") as ColorRect
	if sea != null: sea.color.a = 0.0
	_guard_layer = CanvasLayer.new()
	_guard_layer.name = "SheetSwitchInputLayer"
	_guard_layer.layer = FRONT_LAYER + 1
	add_child(_guard_layer)
	_guard = Control.new()
	_guard.name = "SwitchInputGuard"
	_guard.mouse_filter = Control.MOUSE_FILTER_STOP
	_guard_layer.add_child(_guard)
	_guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_guard.hide()
	_apply_layout()
	return true

func _make_sheet(id: String, ancestor: Node, textures: Dictionary) -> void:
	# Separate owner ancestors keep native unique-name lookup and existing signals valid.
	var layer := CanvasLayer.new()
	layer.name = id.to_pascal_case() + "SheetLayer"
	ancestor.add_child(layer)
	_layers[id] = layer
	var sheet := Control.new()
	sheet.name = id.to_pascal_case() + "Sheet"
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(sheet)
	_sheets[id] = sheet
	var shadow := ShadowObject.new()
	shadow.name = "PaperShadow"
	sheet.add_child(shadow)
	shadow.configure(_papers[id])
	shadow.shadow_offset = Vector2(4.0, 5.0)
	shadow.shadow_blur = 6.0
	shadow.shadow_opacity = 0.27
	shadow.ao_radius = 2.0
	shadow.ao_strength = 0.18
	_shadows[id] = shadow
	var mask := PaperMask.new()
	mask.name = "PaperMask"
	mask.texture = _papers[id]
	mask.alpha_image = _paper_images[id] as Image
	mask.theme = _captured_themes[id] as Theme
	mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	mask.clip_contents = true
	mask.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	mask.z_index = 1
	sheet.add_child(mask)
	_masks[id] = mask
	var tab := Control.new()
	tab.name = id.to_pascal_case() + "Corner"
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.z_index = 50
	sheet.add_child(tab)
	_tabs[id] = tab
	var note := TextureRect.new()
	note.name = "Note"
	note.texture = textures.get(id + "_note", textures.get("design_note")) as Texture2D
	if note.texture == null: note.texture = textures.get("note") as Texture2D
	note.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	note.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(note)
	note.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var icon := NoteIcon.new()
	icon.name = "Icon"
	icon.kind = id
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(icon)
	icon.position = Vector2(27, 15)
	icon.size = Vector2(28, 28)
	var title := Label.new()
	title.name = "Title"
	title.text = {"map":"世界", "edit":"编辑", "cultivate":"培养", "spread":"传播"}[id]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_color", Color("39382e"))
	title.add_theme_font_size_override("font_size", 14)
	tab.add_child(title)
	title.position = Vector2(2, 45)
	title.size = Vector2(78, 24)

func _capture_owners(node: Node) -> Dictionary:
	var result := {node:node.owner}
	for child in node.get_children(): result.merge(_capture_owners(child))
	return result

func _inherited_theme(node: Control) -> Theme:
	var ancestor: Node = node
	while ancestor != null:
		if ancestor is Control and ancestor.theme != null: return ancestor.theme
		ancestor = ancestor.get_parent()
	return null

func _reparent_content(node: Control, mask: Control, _depth: int) -> void:
	var previous_owner := node.owner
	var inherited_theme := _inherited_theme(node)
	node.reparent(mask, false)
	if previous_owner != null and previous_owner.is_ancestor_of(node): node.owner = previous_owner
	if inherited_theme != null: node.theme = inherited_theme
	_same_clip_depth(node)
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _same_clip_depth(node: Node) -> void:
	# Godot alpha clip groups exclude descendants sorted into a different Z bucket.
	if node is CanvasItem: node.z_index = 0
	for child in node.get_children(): _same_clip_depth(child)

func _reparent_finish() -> void:
	# Screen-texture finishing must read the completed alpha group, not its offscreen buffer.
	_finish_copy = BackBufferCopy.new()
	_finish_copy.name = "MapFinishCopy"
	_finish_copy.copy_mode = BackBufferCopy.COPY_MODE_RECT
	_finish_copy.z_index = 2
	(_sheets.map as Control).add_child(_finish_copy)
	var previous_owner := _map_finish.owner
	_map_finish.reparent(_sheets.map, false)
	if previous_owner != null: _map_finish.owner = previous_owner
	_map_finish.z_index = 2
	_map_finish.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var original := _map_finish.material as ShaderMaterial
	if original != null and original.shader != null:
		var finish := original.duplicate() as ShaderMaterial
		var shader := Shader.new()
		shader.code = original.shader.code.replace("void fragment() {", "uniform sampler2D paper_mask : filter_linear, repeat_disable;\n\nvoid fragment() {").replace("map.a);", "map.a * texture(paper_mask, UV).a);")
		finish.shader = shader
		finish.set_shader_parameter("paper_mask", _papers.map)
		_map_finish.material = finish

func _isolate_water_group() -> void:
	_water_terrain = _map_input.get_node_or_null("World/Terrain") as Node2D
	if _water_terrain == null: return
	_water_source = _water_terrain.get_node_or_null("Water") as CanvasGroup
	if _water_source == null: return
	# CanvasGroup and alpha clipping share a backbuffer; never nest their draws.
	_water_source.get_node("Fill").hide()
	_water_viewport = SubViewport.new()
	_water_viewport.name = "MergedWaterViewport"
	_water_viewport.transparent_bg = true
	_water_viewport.disable_3d = true
	_water_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_water_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_water_viewport.gui_disable_input = true
	add_child(_water_viewport)
	_water_ink = WaterInk.new()
	_water_ink.name = "OpaqueWaterInk"
	_water_ink.terrain = _water_terrain
	_water_viewport.add_child(_water_ink)
	_water_composite = WaterComposite.new()
	_water_composite.name = "MergedWaterComposite"
	_water_composite.show_behind_parent = true
	_water_composite.image = _water_viewport.get_texture()
	_water_terrain.add_child(_water_composite)

func _process(_delta: float) -> void:
	_sync_water_view()

func _sync_water_view() -> void:
	if _water_viewport == null or _water_terrain.world == null or _map_input.size.x <= 0.0 or _map_input.size.y <= 0.0: return
	var world_layer := _map_input.get_node("World") as Node2D
	var view := world_layer.transform * _water_terrain.transform
	var final_scale := get_viewport().get_final_transform().get_scale().abs()
	var pixels := Vector2i((_map_input.size * final_scale).ceil()).max(Vector2i.ONE)
	var opacity: float = _water_terrain.water_opacity if _water_source.visible else 0.0
	var signature: Array = [_water_terrain.world, view, _map_input.size, pixels, opacity]
	if signature == _water_signature: return
	_water_signature = signature
	_water_refreshes += 1
	_water_viewport.size = pixels
	_water_ink.transform = Transform2D.IDENTITY.scaled(Vector2(pixels) / _map_input.size) * view
	_water_ink.queue_redraw()
	_water_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_water_composite.view = view
	_water_composite.map_size = _map_input.size
	_water_composite.opacity = opacity
	_water_composite.queue_redraw()

func layout_area(rectangle: Rect2) -> void:
	if not rectangle.position.is_finite() or not rectangle.size.is_finite() or rectangle.size.x <= 0.0 or rectangle.size.y <= 0.0:
		return
	if rectangle.is_equal_approx(_area): return
	var interrupted := _switching
	if _switching:
		if _tween != null: _tween.kill()
		_active = _switch_target
		_order.erase(_active)
		_order.append(_active)
		_switching = false
		_guard.hide()
		_map_input.mouse_filter = _saved_map_filter
	else:
		_capture_offsets()
	_area = rectangle
	_apply_layout()
	if interrupted: switch_completed.emit(_active)

func _capture_offsets() -> void:
	for id in _sheets:
		var sheet := _sheets[id] as Control
		if _settled.has(id): _offsets[id] += sheet.position - Vector2(_settled[id])
		_settled[id] = sheet.position

func _rest_position(id: String) -> Vector2:
	return _area.position + Vector2(_offsets[id]) + _back_offset(id)

func _opaque_body_uv(image: Image) -> Rect2:
	if image == null or image.is_empty(): return Rect2()
	var rgba := image.duplicate() as Image
	rgba.convert(Image.FORMAT_RGBA8)
	var data := rgba.get_data()
	var width := rgba.get_width()
	var height := rgba.get_height()
	var left := 0
	var top := 0
	var right := width
	var bottom := height
	# Cache the shared opaque interior, excluding transparent margins.
	for index in 33:
		var y := clampi(roundi(lerpf(height * .1, height * .9, float(index) / 32.0)), 0, height - 1)
		var first := 0
		var last := width - 1
		while first < width and data[(y * width + first) * 4 + 3] < 242: first += 1
		while last >= first and data[(y * width + last) * 4 + 3] < 242: last -= 1
		if first > last: return Rect2()
		left = maxi(left, first)
		right = mini(right, last + 1)
		var x := clampi(roundi(lerpf(width * .1, width * .9, float(index) / 32.0)), 0, width - 1)
		first = 0
		last = height - 1
		while first < height and data[(first * width + x) * 4 + 3] < 242: first += 1
		while last >= first and data[(last * width + x) * 4 + 3] < 242: last -= 1
		if first > last: return Rect2()
		top = maxi(top, first)
		bottom = mini(bottom, last + 1)
	# Include folded corners while ignoring the outer two-percent fiber fringe.
	var fringe_x := maxi(1, ceili(width * .02))
	var fringe_y := maxi(1, ceili(height * .02))
	var horizontal_from := left + fringe_x
	var horizontal_to := right - fringe_x
	var vertical_from := top + fringe_y
	var vertical_to := bottom - fringe_y
	for y in range(vertical_from, vertical_to):
		var first := 0
		var last := width - 1
		while first < width and data[(y * width + first) * 4 + 3] < 242: first += 1
		while last >= first and data[(y * width + last) * 4 + 3] < 242: last -= 1
		if first > last: return Rect2()
		left = maxi(left, first)
		right = mini(right, last + 1)
	for x in range(horizontal_from, horizontal_to):
		var first := 0
		var last := height - 1
		while first < height and data[(first * width + x) * 4 + 3] < 242: first += 1
		while last >= first and data[(last * width + x) * 4 + 3] < 242: last -= 1
		if first > last: return Rect2()
		top = maxi(top, first)
		bottom = mini(bottom, last + 1)
	return Rect2(Vector2(left, top) / Vector2(width, height), Vector2(right - left, bottom - top) / Vector2(width, height))

func _back_offset(id: String) -> Vector2:
	return _depth_offset(_order.size() - 1 - _order.find(id))

func _depth_offset(depth: int) -> Vector2:
	if depth <= 0: return Vector2.ZERO
	# Keep every exposed corner reachable as the stack grows beyond two sheets.
	return Vector2(BACK_OFFSET.x - 6.0 * (depth - 1), BACK_OFFSET.y * depth)

func _apply_layout() -> void:
	if _area.size.x <= 0.0 or _area.size.y <= 0.0: return
	for id in _sheets:
		var sheet := _sheets[id] as Control
		sheet.position = _rest_position(id)
		sheet.size = _area.size
		sheet.pivot_offset = sheet.size * 0.5
		sheet.rotation = _rest_rotation(id)
		(_layers[id] as CanvasLayer).layer = FRONT_LAYER - (_order.size() - 1 - _order.find(id))
		var mask := _masks[id] as Control
		mask.position = Vector2.ZERO
		mask.size = sheet.size
		var tab := _tabs[id] as Control
		var body: Rect2 = _body_uv.get(id,Rect2(0,0,1,1))
		tab.position = Vector2(body.position.x*sheet.size.x-45.0,142.0+SHEET_IDS.find(id)*80.0)
		tab.size = Vector2(82.0, 82.0)
		(_shadows[id] as Control).sync_from(mask)
		_settled[id] = sheet.position
	for id in _contents:
		var host := _contents[id] as Control
		var body: Rect2 = _body_uv[id]
		host.position = body.position * _area.size + Vector2(18, 18)
		host.size = (body.size * _area.size - Vector2(36, 36)).max(Vector2.ONE)
	for content in [_map_input, _map_finish, _spread]:
		if is_instance_valid(content): content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _finish_copy != null: _finish_copy.rect = Rect2(Vector2.ZERO, _area.size)

func select_sheet(id: String) -> bool:
	id = _canonical(id)
	if _switching or not _sheets.has(id) or not _area.has_area(): return false
	if id == _active: return true
	_capture_offsets()
	_switching = true
	_switch_target = id
	_saved_map_filter = _map_input.mouse_filter
	_map_input.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guard.show()
	switch_started.emit(id)
	var sheet := _sheets[id] as Control
	var pulled := sheet.position + Vector2(-88.0, -14.0)
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(sheet, "position", pulled, 0.2)
	_tween.tween_callback(func() -> void:
		_active = id
		_order.erase(id)
		_order.append(id)
		for key in _sheets:
			(_layers[key] as CanvasLayer).layer = FRONT_LAYER - (_order.size() - 1 - _order.find(key))
	)
	_tween.set_parallel(true)
	_tween.tween_property(sheet, "position", _area.position + Vector2(_offsets[id]), 0.3)
	_tween.tween_property(sheet, "rotation", 0.0, 0.3)
	for other_id in _sheets:
		if other_id == id: continue
		# The callback reorders papers before these target values are evaluated.
		var depth := _order.size() - 1 - _order.find(other_id)
		if _order.find(other_id) > _order.find(id): depth += 1
		_tween.tween_property(_sheets[other_id], "position", _area.position + Vector2(_offsets[other_id]) + _depth_offset(depth), 0.3)
		_tween.tween_property(_sheets[other_id], "rotation", (-0.012 if depth % 2 == 1 else 0.009), 0.3)
	_tween.chain().tween_callback(func() -> void:
		_switching = false
		_apply_layout()
		_guard.hide()
		_map_input.mouse_filter = _saved_map_filter
		switch_completed.emit(id)
	)
	return true

func is_switching() -> bool:
	return _switching

func active_sheet() -> String:
	return _active

func map_rect() -> Rect2:
	if not is_instance_valid(_map_input): return Rect2()
	return _map_input.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _map_input.size)

func sheet_node(id: String) -> Control:
	return _sheets.get(_canonical(id)) as Control

func tab_node(id: String) -> Control:
	return _tabs.get(_canonical(id)) as Control

func export_offsets() -> Dictionary:
	var result := {}
	for id in _sheets:
		var offset: Vector2 = _offsets[id] if _switching else (_sheets[id] as Control).position - _area.position - _back_offset(id)
		result[id] = {"x":offset.x,"y":offset.y}
	return result

func import_offsets(offsets: Dictionary, bounds: Rect2 = Rect2()) -> PackedStringArray:
	var errors := PackedStringArray()
	if _switching or not _area.has_area():
		errors.append("Paper is switching or not configured.")
		return errors
	var targets := {}
	for key in offsets:
		var id := _canonical(str(key))
		if not _sheets.has(id) or targets.has(id):
			errors.append("Unknown or duplicate paper: %s" % key)
			continue
		var value: Variant = offsets[key]
		if not value is Dictionary or not _number(value.get("x")) or not _number(value.get("y")):
			errors.append("Invalid paper offset: %s" % id)
			continue
		targets[id] = Vector2(float(value.x), float(value.y))
	if not errors.is_empty(): return errors
	if not bounds.has_area(): bounds = get_viewport_rect().grow(96.0)
	for id in targets:
		var sheet := _sheets[id] as Control
		var tab := _tabs[id] as Control
		var target: Vector2 = _area.position + Vector2(targets[id]) + _back_offset(id)
		var transform := sheet.get_global_transform_with_canvas()
		transform.origin += sheet.get_canvas_transform().basis_xform(target - sheet.position)
		if not bounds.encloses(transform * Rect2(tab.position, tab.size)):
			errors.append("Paper tab out of bounds: %s" % id)
	if not errors.is_empty(): return errors
	_capture_offsets()
	for id in targets: _offsets[id] = targets[id]
	_apply_layout()
	return errors

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func inspection() -> Dictionary:
	var sheets := {}
	for id in _sheets:
		var sheet := _sheets[id] as Control
		var tab := _tabs[id] as Control
		var mask := _masks[id] as PaperMask
		sheets[id] = {"position":sheet.position,"rotation":sheet.rotation,"rect":sheet.get_global_transform_with_canvas()*Rect2(Vector2.ZERO,sheet.size),"layer":(_layers[id] as CanvasLayer).layer,"tab_local_rect":Rect2(tab.position,tab.size),"tab_is_button":tab is BaseButton,"tab_has_tape":tab.has_node("ClearTape"),"tab_has_icon":tab.has_node("Icon"),"paper_texture":mask.texture.resource_path,"clip_children":mask.clip_children,"alpha_mask":mask.alpha_image!=null,"shadow":(_shadows[id] as Control).inspection()}
	return {"water_compositing":"Opaque vector river/lake mesh merged in a transparent viewport before one zoom-opacity application; no nested clip/backbuffer", "water_refreshes":_water_refreshes, "water_viewport_size":_water_viewport.size if _water_viewport != null else Vector2i.ZERO, "layout_version":6,"order":_order.duplicate(),"active":_active,"switching":_switching,"area":_area,"map_rect":map_rect(),"sheets":sheets,"owners_preserved":_owners.get("map_input")==_map_input.owner and _owners.get("map_finish")==_map_finish.owner and _owners.get("spread")==_spread.owner and _owners.get("workbench")==_workbench.owner,"full_sheet_map":_map_input.position.is_zero_approx() and _map_input.size.is_equal_approx(_area.size),"paper_texture":_paper.resource_path if _paper!=null else "","workbench_theme_preserved":_captured_themes.get("edit")!=null and (_masks.edit as Control).theme==_captured_themes.edit,"workbench_font_color":_workbench.get_theme_color("font_color","Label"),"paper_offsets":export_offsets(),"switch_seconds":0.5}

func content_host(id: String) -> Control:
	return _contents.get(_canonical(id)) as Control

func _rest_rotation(id: String) -> float:
	if id == _active: return 0.0
	return -0.012 if (_order.size() - 1 - _order.find(id)) % 2 == 1 else 0.009

func _canonical(id: String) -> String:
	return "edit" if id in ["design", "meme"] else id


func tab_control(id: String) -> Control:
	return _tabs.get(id) as Control
