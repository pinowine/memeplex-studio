## 将二维显示内容贴到模型屏幕，并把点击位置映射回源控件。
extends Node

const MemeScreen := preload("res://scripts/presentation/studio/devices/monitor/desk_meme_monitor.gd")
const InventoryScreen := preload("res://scripts/presentation/studio/devices/monitor/desk_crt_inventory_screen.gd")
const PIXEL_WIDTH := 600

var _target: MeshInstance3D
var _source: Control
var _source_rect := Rect2()
var _viewport: SubViewport
var _meme: Control
var _inventory: Control
var _label: Label
var _background: ColorRect
var _screen_size_px := Vector2i.ZERO
var _uv_min := Vector2.ZERO
var _uv_max := Vector2.ONE
var _uv_origin := Vector3.ZERO
var _uv_x := Vector3.ZERO
var _uv_y := Vector3.ZERO
var _physical_size := Vector2.ZERO
var _presentation_hash := 0
var _synced := false
var _last_mode := ""
var _errors: Array[String] = []

func configure(target: MeshInstance3D, source: Control, source_rect: Rect2, _logical: SubViewport = null) -> bool:
	if is_instance_valid(_viewport):
		_errors.append("Screen surface is already configured")
		return false
	_target = target
	_source = source
	_source_rect = source_rect
	if not is_instance_valid(_target) or not is_instance_valid(_source) or _target.mesh == null:
		_errors.append("Screen surface requires a mesh and an authoritative Control")
		return false
	if not _measure_uv_frame():
		_errors.append("Screen surface requires a nondegenerate UV triangle")
		return false
	_screen_size_px = Vector2i(PIXEL_WIDTH, maxi(32, roundi(PIXEL_WIDTH * _physical_size.y / _physical_size.x)))
	_viewport = SubViewport.new()
	_viewport.name = "FixedAspectScreenContent"
	_viewport.size = _screen_size_px
	_viewport.disable_3d = true
	_viewport.world_2d = World2D.new()
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_viewport)
	_background = ColorRect.new()
	_background.name = "ScreenBackground"
	_background.color = Color("06140b")
	_background.size = Vector2(_screen_size_px)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_background)
	if _source.has_method("screen_presentation"):
		_meme = MemeScreen.new()
		_meme.name = "MemePresentationMirror"
		_meme.theme = _source.theme
		_meme.font_size = 20
		_meme.screen_padding = 18.0
		_meme.curve_height = 176.0
		_viewport.add_child(_meme)
		_meme.layout_screen(Rect2(Vector2.ZERO, Vector2(_screen_size_px)))
		_inventory = InventoryScreen.new()
		_inventory.name = "InventoryPresentationMirror"
		_inventory.theme = _source.theme
		_inventory.size = Vector2(_screen_size_px)
		_inventory.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_viewport.add_child(_inventory)
	elif _source is Label:
		_background.color = Color("b7c99a")
		_label = Label.new()
		_label.name = "FixedAspectNumberLabel"
		_label.size = Vector2(_screen_size_px)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_override("font", _source.get_theme_font("font"))
		_label.add_theme_color_override("font_color", _source.get_theme_color("font_color"))
		_viewport.add_child(_label)
	else:
		_errors.append("Unsupported screen presentation source: " + _source.get_class())
		return false
	var material := StandardMaterial3D.new()
	material.resource_name = "FixedAspectScreenPresentation"
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.uv1_scale = Vector3(1.0 / (_uv_max.x-_uv_min.x), 1.0 / (_uv_max.y-_uv_min.y), 1.0)
	material.uv1_offset = Vector3(-_uv_min.x / (_uv_max.x-_uv_min.x), -_uv_min.y / (_uv_max.y-_uv_min.y), 0.0)
	_target.material_override = material
	sync()
	return true

func _process(_delta: float) -> void:
	sync()

func sync() -> void:
	if not is_instance_valid(_source) or not is_instance_valid(_viewport): return
	if _source.has_method("screen_presentation"):
		_source_rect = _source.get("_screen_rect")
	if _label != null:
		var ink := _source.get_theme_color("font_color")
		if _label.get_theme_color("font_color") != ink:
			_label.add_theme_color_override("font_color", ink)
		var text := (_source as Label).text
		if _synced and text == _label.text: return
		_label.text = text
		var font := _label.get_theme_font("font")
		var font_size := clampi(roundi(_screen_size_px.y * 0.44), 18, 96)
		while font_size > 12 and (font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > _screen_size_px.x-24 or font.get_height(font_size) > _screen_size_px.y-12):
			font_size -= 1
		_label.add_theme_font_size_override("font_size", font_size)
		_synced = true
		return
	var presentation: Dictionary = _source.screen_presentation()
	var state_hash := hash(presentation)
	if _synced and state_hash == _presentation_hash: return
	_presentation_hash = state_hash
	_synced = true
	_last_mode = str(presentation.get("mode", "meme"))
	_meme.apply_presentation(presentation.get("meme", {}))
	_meme.visible = _last_mode == "meme"
	_inventory.visible = _last_mode != "meme"
	_inventory.sync_inventory(_last_mode, presentation.get("balances", {}), bool(presentation.get("enabled", false)))

## UV 在屏幕外时返回 Vector2.INF；有效结果使用源控件的画布坐标。
func input_from_uv(uv: Vector2) -> Vector2:
	if not is_instance_valid(_source) or not Rect2(Vector2.ZERO, Vector2.ONE).has_point(uv): return Vector2.INF
	if _inventory != null and _last_mode != "meme":
		var original: Control = _source.get("_inventory")
		if original != null:
			var pixel := uv * Vector2(_screen_size_px)
			for index in 4:
				var rendered: Rect2 = _inventory.cell_rect(index)
				if rendered.has_point(pixel):
					var source_cell: Rect2 = original.cell_rect(index)
					var fraction := (pixel-rendered.position)/rendered.size
					return original.get_global_transform_with_canvas()*(source_cell.position+fraction*source_cell.size)
			return original.get_global_transform_with_canvas()*Vector2.ZERO
	elif _meme != null:
		var original: Control = _source.get("_meme")
		if original != null:
			var rendered: Rect2 = _meme.inspection().title_rect
			var pixel := uv*Vector2(_screen_size_px)
			if rendered.has_point(pixel):
				var source_title: Rect2 = original.inspection().title_rect
				return original.get_global_transform_with_canvas()*(source_title.position+(pixel-rendered.position)/rendered.size*source_title.size)
	return _source.get_global_transform_with_canvas()*(_source_rect.position+uv*_source_rect.size)

## 将世界空间射线投到屏幕表面；未命中时返回 Vector2.INF。
func input_from_ray(ray_origin_world: Vector3, ray_direction_world: Vector3) -> Vector2:
	if not is_instance_valid(_target) or not _target.is_visible_in_tree(): return Vector2.INF
	var ray_origin_local := _target.to_local(ray_origin_world)
	var ray_direction_local := _target.global_basis.inverse()*ray_direction_world
	var normal := _uv_x.cross(_uv_y).normalized()
	var hit: Variant = Plane(normal, _uv_origin).intersects_ray(ray_origin_local, ray_direction_local)
	if hit == null: return Vector2.INF
	var delta: Vector3 = hit-_uv_origin
	var xx := _uv_x.dot(_uv_x)
	var yy := _uv_y.dot(_uv_y)
	var xy := _uv_x.dot(_uv_y)
	var determinant := xx*yy-xy*xy
	if determinant<=maxf(0.000000000000000000000001, xx*yy*0.0000000001): return Vector2.INF
	var uv := Vector2((delta.dot(_uv_x)*yy-delta.dot(_uv_y)*xy)/determinant, (delta.dot(_uv_y)*xx-delta.dot(_uv_x)*xy)/determinant)
	return input_from_uv((uv-_uv_min)/(_uv_max-_uv_min))

func _measure_uv_frame() -> bool:
	_uv_min = Vector2.INF
	_uv_max = -Vector2.INF
	var found := false
	for surface in _target.mesh.get_surface_count():
		var arrays: Array = _target.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if uvs.size()!=vertices.size(): continue
		for uv in uvs:
			_uv_min = _uv_min.min(uv)
			_uv_max = _uv_max.max(uv)
		if found: continue
		for a in range(1, vertices.size()):
			for b in range(a+1, vertices.size()):
				var d1 := uvs[a]-uvs[0]
				var d2 := uvs[b]-uvs[0]
				var det := d1.cross(d2)
				if absf(det)<0.00001: continue
				_uv_x = ((vertices[a]-vertices[0])*d2.y-(vertices[b]-vertices[0])*d1.y)/det
				_uv_y = ((vertices[b]-vertices[0])*d1.x-(vertices[a]-vertices[0])*d2.x)/det
				_uv_origin = vertices[0]-_uv_x*uvs[0].x-_uv_y*uvs[0].y
				found = true
				break
			if found: break
	if not found or _uv_max.x<=_uv_min.x or _uv_max.y<=_uv_min.y: return false
	_physical_size = Vector2((_target.global_basis*_uv_x).length()*(_uv_max.x-_uv_min.x), (_target.global_basis*_uv_y).length()*(_uv_max.y-_uv_min.y))
	return _physical_size.x>0.00001 and _physical_size.y>0.00001

func inspection() -> Dictionary:
	return {"component":"fixed_aspect_screen_presentation", "pixel_size":_screen_size_px, "physical_size_m":_physical_size, "pixel_aspect":float(_screen_size_px.x)/maxi(1,_screen_size_px.y), "physical_aspect":_physical_size.x/maxf(_physical_size.y,0.00001), "source_rect":_source_rect, "mode":_last_mode, "independent_viewport":true, "authoritative_source_reparented":false, "input_mapping":"inventory_cell_inverse_then_source_canvas", "meme":_meme.inspection() if _meme != null else {}, "inventory":_inventory.inspection() if _inventory != null else {}, "label_text":_label.text if _label != null else "", "label_font_size":_label.get_theme_font_size("font_size") if _label != null else 0, "background_color":_background.color if _background != null else Color.TRANSPARENT, "label_font_color":_label.get_theme_color("font_color") if _label != null else Color.TRANSPARENT, "errors":_errors.duplicate()}
