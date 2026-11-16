extends Node2D

class BorderInk extends Node2D:
	var terrain: Node2D
	func _draw() -> void:
		terrain.draw_borders(self)

var _terrain: Node2D
var _viewport: SubViewport
var _ink: BorderInk
var _view := Transform2D.IDENTITY
var _map_size := Vector2.ZERO
var _signature: Array = []
var _pending_signature: Array = []
var _live_signature: Array = []
var _cached := false
var _ink_material: CanvasItemMaterial

func configure(terrain: Node2D) -> void:
	_terrain = terrain
	_ink_material = CanvasItemMaterial.new()
	_ink_material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_viewport = SubViewport.new()
	_viewport.name = "BorderViewport"
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_ink = BorderInk.new()
	_ink.terrain = terrain
	_viewport.add_child(_ink)

func _process(_delta: float) -> void:
	if _terrain.world == null or not is_visible_in_tree(): return
	var world_layer := _terrain.get_parent() as Node2D
	var map_input := world_layer.get_parent() as Control
	var view := world_layer.transform * _terrain.transform
	var pixel_scale := (get_viewport().get_final_transform().get_scale().abs() * map_input.get_global_transform_with_canvas().get_scale().abs()).ceil()
	var pixels := Vector2i((map_input.size * pixel_scale).ceil()).max(Vector2i.ONE)
	var signature: Array = [_terrain.world, view, map_input.size, pixels, _terrain.zoom_value, _terrain.selected_country]
	if signature == _signature:
		if not _cached:
			_cached = true
			material = _ink_material
			queue_redraw()
		_pending_signature = signature
		return
	# Draw moving views directly so navigation does not bake a texture each frame.
	if signature != _pending_signature:
		_pending_signature = signature
		var live_signature: Array = [_terrain.world, _terrain.zoom_value, _terrain.selected_country]
		if _cached or live_signature != _live_signature:
			_cached = false
			_live_signature = live_signature
			material = null
			queue_redraw()
		return
	_signature = signature
	_cached = true
	material = _ink_material
	_view = view
	_map_size = map_input.size
	_viewport.size = pixels
	_viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(pixels) / _map_size) * view
	_ink.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()

func _draw() -> void:
	if not _cached:
		_terrain.draw_borders(self)
		return
	draw_set_transform_matrix(_view.affine_inverse())
	draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, _map_size), false)
