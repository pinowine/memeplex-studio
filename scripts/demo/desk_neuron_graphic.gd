class_name DeskNeuronGraphic
extends Control

const Surface=preload("res://scripts/demo/desk_neuron_surface.gd")
var _identity := "module"
var _kernel_id := "stance"
var _growth := 0.0
var _target_growth := 1.0
var _surface: Control

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	tooltip_text=""
	_surface=Surface.new()
	_surface.name="NeuronSurface"
	add_child(_surface)
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_refresh)
	_refresh()

func configure(identity: String,kernel_id: String="stance") -> void:
	if _identity==identity and _kernel_id==kernel_id:return
	_identity=identity
	_kernel_id=kernel_id
	_growth=0.0
	_refresh()

func set_growth(value: float) -> void:
	if not is_finite(value):return
	_growth=clampf(value,0.0,1.0)
	_target_growth=_growth
	_refresh()

func grow() -> void:
	_target_growth=1.0

func _process(delta: float) -> void:
	if _growth==_target_growth:return
	_growth=move_toward(_growth,_target_growth,maxf(delta,0)*.85)
	_refresh()

func _refresh() -> void:
	if _surface==null:return
	var radius := maxf(1.0,minf(size.x,size.y)*.078)
	_surface.set_network([{"center":size*.5,"radius":radius,"identity":_identity,"kernel_id":_kernel_id,"growth":_growth}])

func inspection() -> Dictionary:
	return {"identity":_identity,"kernel_id":_kernel_id,"growth":_growth,"renderer_api":"shared_procedural_neuron",
		"surface":_surface.inspection() if _surface!=null else {},"mouse_filter":mouse_filter,"tooltip":tooltip_text}
