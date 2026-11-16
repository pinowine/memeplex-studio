extends Node2D

var _terrain: Node2D
var _live: MeshInstance2D
var _ink: MeshInstance2D
var _viewport: SubViewport
var _ink_material: CanvasItemMaterial
var _signature: Array = []
var _pending_signature: Array = []
var _view := Transform2D.IDENTITY
var _map_size := Vector2.ZERO

func configure(terrain: Node2D) -> void:
	_terrain = terrain
	_live = preload("res://scripts/presentation/map/map_border_mesh.gd").new()
	_live.name = "StaticGeometry"
	add_child(_live)
	_ink_material = CanvasItemMaterial.new()
	_ink_material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_viewport = SubViewport.new()
	_viewport.name = "BorderViewport"
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_ink = MeshInstance2D.new()
	_viewport.add_child(_ink)

func set_lines(points: PackedVector2Array, ink: Color, width: float) -> void:
	_live.set_lines(points, ink, width)
	_ink.mesh = _live.mesh
	_ink.self_modulate = ink
	_signature.clear()
	_pending_signature.clear()
	_live.show()
	material = null
	queue_redraw()

func _process(_delta: float) -> void:
	if _terrain.world == null or not is_visible_in_tree(): return
	var world_layer := _terrain.get_parent() as Node2D
	var map_input := world_layer.get_parent() as Control
	var view := world_layer.transform * _terrain.transform
	var pixel_scale := (get_viewport().get_final_transform().get_scale().abs() * map_input.get_global_transform_with_canvas().get_scale().abs()).ceil()
	var pixels := Vector2i((map_input.size * pixel_scale).ceil()).max(Vector2i.ONE)
	var signature: Array = [_terrain.world, view, map_input.size, pixels]
	if signature == _signature:
		if _live.visible:
			_live.hide()
			material = _ink_material
			queue_redraw()
		_pending_signature = signature
		return
	if signature != _pending_signature:
		_pending_signature = signature
		if not _live.visible:
			_live.show()
			material = null
			queue_redraw()
		return
	# Moving views reuse the mesh; settled views reuse pixels to save GPU work.
	_signature = signature
	_live.hide()
	material = _ink_material
	_view = view
	_map_size = map_input.size
	_viewport.size = pixels
	_viewport.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(pixels) / _map_size) * view
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()

func _draw() -> void:
	if _live.visible: return
	draw_set_transform_matrix(_view.affine_inverse())
	draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, _map_size), false)
