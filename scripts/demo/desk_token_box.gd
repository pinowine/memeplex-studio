class_name DeskTokenBox
extends Control

const Graphic := preload("res://scripts/demo/desk_context_resource_graphic.gd")
const Box := preload("res://assets/desk/v10/token_box.png")
const IDS := {"stance":["freedom","authority","equality","hierarchy"],"pragmatic":["sincere","ironic","support","opposition"]}
var layer := "stance"
var _rules: Resource
var _balances: Dictionary = {}
var _background: TextureRect
var _icons: Array[Control] = []
var _count: Label
var _hover := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = ""
	_background = TextureRect.new()
	_background.name = "CompartmentBox"
	var atlas := AtlasTexture.new()
	atlas.atlas = Box
	atlas.region = Rect2(125,133,1005,990)
	_background.texture = atlas
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	for index in 4:
		var graphic := Graphic.new()
		graphic.name = "TokenCell%d" % index
		add_child(graphic)
		_icons.append(graphic)
	_count = Label.new()
	_count.name = "HoveredTokenCount"
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size",20)
	_count.add_theme_color_override("font_color",Color("f1e3b8"))
	_count.add_theme_color_override("font_shadow_color",Color("171a14"))
	_count.add_theme_constant_override("shadow_offset_x",1)
	_count.add_theme_constant_override("shadow_offset_y",2)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)
	_count.hide()
	mouse_exited.connect(func() -> void: _hover=-1; _count.hide(); queue_redraw())
	resized.connect(_layout)
	_layout()
	_refresh()

func configure(id: String,rules: Resource) -> void:
	layer=id
	_rules=rules
	_refresh()

func sync_state(snapshot: Dictionary) -> void:
	var design: Dictionary = snapshot.get("design_state",snapshot)
	_balances=design.get("context_token_balances",{}).duplicate(true)
	_refresh()

func _refresh() -> void:
	if _rules == null or _icons.is_empty(): return
	for index in 4:
		var id: String=IDS[layer][index]
		var definition: Dictionary=_rules.context_resource(id)
		_icons[index].configure(definition)
		_icons[index].modulate.a = 1.0 if int(_balances.get(id,0))>0 else .25
	if _hover>=0: _count.text=str(int(_balances.get(IDS[layer][_hover],0)))
	queue_redraw()

func _layout() -> void:
	if _background==null: return
	_background.size=size
	for index in _icons.size():
		_icons[index].position=size*Vector2(.15+float(index%2)*.47,.15+float(index/2)*.47)
		_icons[index].size=size*Vector2(.25,.25)
	if _count!=null:
		_count.size=Vector2(34,28)
		if _hover>=0: _count.position=cell_rect(_hover).get_center()-_count.size*.5

func cell_rect(index: int) -> Rect2:
	return Rect2(size*Vector2(.065+float(index%2)*.465,.065+float(index/2)*.465),size*Vector2(.405,.405))

func background_node() -> TextureRect:
	return _background

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover=-1
		for index in 4:
			if cell_rect(index).has_point(event.position): _hover=index
		_count.visible=_hover>=0
		if _hover>=0:
			_count.text=str(int(_balances.get(IDS[layer][_hover],0)))
			_count.position=cell_rect(_hover).get_center()-_count.size*.5
		queue_redraw()

func _draw() -> void:
	for index in 4:
		var amount := int(_balances.get(IDS[layer][index],0))
		var rect := cell_rect(index)
		for level in mini(amount,5):
			draw_arc(rect.get_center()+Vector2(0,9+level*1.7),size.x*.117,.04,PI-.04,18,Color(.85,.75,.45,.6),.9,true)
	if _hover>=0: draw_style_box(_hover_style(),cell_rect(_hover).grow(-1))

func _hover_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0,0,0,.35)
	style.set_border_width_all(1)
	style.border_color=Color(.8,.75,.58,.6)
	return style

func inspection() -> Dictionary:
	return {"layer":layer,"ids":IDS[layer].duplicate(),"balances":_balances.duplicate(),"hovered":_hover,"hover_count":_count.text if _hover>=0 else "","cells":range(4).map(func(index: int)->Rect2:return get_global_transform_with_canvas()*cell_rect(index)),"icons":_icons.map(func(icon: Control)->Dictionary:return icon.inspection()),"popup":"count only"}
