extends Control

const Geometry=preload("res://scripts/demo/desk_neuron_geometry.gd")
const InkShader=preload("res://shaders/desk_neuron_ink_v10.gdshader")
const PIXEL_SCALE := 2
var _cells: Array=[]
var _links: Array=[]
var _stamp := ""
var _updates := 0
var _viewport: SubViewport
var _painter: MaskPainter
var _display: TextureRect

class MaskPainter extends Node2D:
	var mesh: ArrayMesh
	func _draw() -> void:
		if mesh!=null and mesh.get_surface_count()>0:draw_mesh(mesh,null)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	tooltip_text=""
	_viewport=SubViewport.new()
	_viewport.transparent_bg=true
	_viewport.disable_3d=true
	_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_painter=MaskPainter.new()
	_viewport.add_child(_painter)
	_display=TextureRect.new()
	_display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_display.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_display.texture=_viewport.get_texture()
	_display.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	var pencil := ShaderMaterial.new()
	pencil.shader=InkShader
	_display.material=pencil
	_display.show_behind_parent=true
	add_child(_display)
	resized.connect(_invalidate)
	_redraw_mask()

func _invalidate() -> void:
	_stamp=""
	_redraw_mask()

func set_network(cells: Array,links: Array=[]) -> void:
	_cells=cells.duplicate(true)
	_links=links.duplicate(true)
	_redraw_mask()

func _redraw_mask() -> void:
	if _viewport==null or size.x<=0 or size.y<=0:return
	var signature := str(size)+JSON.stringify([_cells,_links])
	if signature==_stamp:return
	_stamp=signature
	var polygons: Array[PackedVector2Array]=[]
	for record: Dictionary in _cells:
		polygons.append_array(Geometry.cell(record.center,float(record.radius),str(record.identity),str(record.kernel_id),float(record.get("growth",1.0))))
	for link: Dictionary in _links:
		if link.get("arbor",false):
			polygons.append_array(Geometry.arbor(link.points,float(link.get("growth",1.0)),float(link.get("width",.7)),str(link.get("identity","extension"))))
		else:polygons.append_array(Geometry.stroke(link.points,float(link.get("growth",1.0)),float(link.get("width",.7))))
	_viewport.size=Vector2i(maxi(1,ceili(size.x*PIXEL_SCALE)),maxi(1,ceili(size.y*PIXEL_SCALE)))
	_painter.scale=Vector2.ONE*PIXEL_SCALE
	_painter.mesh=Geometry.mask_mesh(polygons)
	_painter.queue_redraw()
	_display.size=size
	_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	_updates+=1
	queue_redraw()

func _draw() -> void:
	for record: Dictionary in _cells:
		var growth := float(record.get("growth",1.0))
		if growth<=0:continue
		var centre: Vector2=record.center
		var radius := float(record.radius)*.34*minf(growth*4.0,1.0)
		draw_circle(centre,radius+1.0,Color("e4e0cf"))
		draw_arc(centre,radius,0,TAU,20,Color("41483d"),.65,true)
		draw_circle(centre+Vector2(-.4,.2),radius*.43,Color("485046"))

func mask_image() -> Image:
	return _viewport.get_texture().get_image() if _viewport!=null else null

func inspection() -> Dictionary:
	return {"cells":_cells.duplicate(true),"links":_links.duplicate(true),"nucleus_count":_cells.size(),"updates":_updates,"pixel_scale":PIXEL_SCALE,
		"style":"ink_neuronal_arbor","shader":InkShader.resource_path,"mouse_filter":mouse_filter,"tooltip":tooltip_text}
