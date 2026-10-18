class_name DeskContextResourceGraphic
extends Control

const METAL := preload("res://assets/desk/v10/metal_resources.png")
const PAPER := preload("res://assets/desk/v1/blank_print_paper.png")
var definition: Dictionary = {}
var _metal: AtlasTexture

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = ""
	resized.connect(queue_redraw)
	_refresh()

func configure(value: Dictionary) -> void:
	definition = value.duplicate(true)
	_refresh()

func _refresh() -> void:
	var kind := str(definition.get("kind","language"))
	var cell := Vector2.ZERO
	if kind == "group": cell = Vector2(0,1)
	elif kind == "pragmatic_token": cell = Vector2(1,0)
	_metal = AtlasTexture.new()
	_metal.atlas = METAL
	_metal.region = Rect2(cell*Vector2(METAL.get_size())*.5,Vector2(METAL.get_size())*.5)
	queue_redraw()

func _draw() -> void:
	if definition.is_empty(): return
	var kind := str(definition.get("kind",""))
	var title := str(definition.get("title",definition.get("id","")))
	var font := get_theme_default_font()
	if kind == "topic":
		var paper := Rect2(Vector2(size.x*.22,0),Vector2(size.x*.56,size.y))
		draw_texture_rect(PAPER,paper,false,Color("e9e0c7"))
		for index in 7:
			var y := size.y*(.18+float(index)*.11)
			draw_line(Vector2(paper.position.x+6,y),Vector2(paper.end.x-6,y),Color(.3,.28,.22,.15),.8,true)
		for index in title.length():
			var point := Vector2(size.x*.5,size.y*.24+index*minf(18,size.y*.14))
			var glyph := title.substr(index,1)
			draw_string(font,point-Vector2(font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x*.5,0),glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("33392f"))
		return
	var edge := minf(size.x,size.y)
	var rect := Rect2((size-Vector2.ONE*edge)*.5,Vector2.ONE*edge)
	draw_texture_rect(_metal,rect,false)
	var center := rect.get_center()+Vector2(0,-edge*.025 if kind=="group" else 0)
	var radius := edge*(.19 if kind=="group" else .24)
	# The relief shares the same icon strokes at a tiny highlight offset.
	_icon(center+Vector2(.65,.8),radius,Color("c9c1a6"),maxf(1,edge*.026))
	_icon(center,radius,Color("282c26"),maxf(1,edge*.021))
	if kind == "group":
		var font_size := clampi(int(edge*.09),8,12)
		var text_size := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		draw_string(font,Vector2(center.x-text_size.x*.5,rect.position.y+edge*.827),title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("222720"))
	else:
		var count := title.length()
		for index in count:
			var angle := -PI*.76+float(index+1)*PI*1.52/float(count+1)
			var point := center+Vector2(sin(angle),-cos(angle))*edge*.337
			draw_set_transform(point,angle)
			var glyph := title.substr(index,1)
			var font_size := clampi(int(edge*.115),8,13)
			var width := font.get_string_size(glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
			draw_string(font,Vector2(-width*.5,0),glyph,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("30352c"))
			draw_set_transform(Vector2.ZERO)

func _line(points: Array,center: Vector2,radius: float,color: Color,width: float) -> void:
	var poly := PackedVector2Array()
	for point: Vector2 in points: poly.append(center+point*radius)
	draw_polyline(poly,color,width,true)

func _icon(center: Vector2,radius: float,color: Color,width: float) -> void:
	var id := str(definition.get("id",""))
	match id:
		"language_zh":
			_line([Vector2(-.75,-.72),Vector2(.75,-.72),Vector2(.2,-.22),Vector2(-.4,.46),Vector2(-.76,.75)],center,radius,color,width)
			_line([Vector2(-.66,-.1),Vector2(.2,-.1),Vector2(.38,.35),Vector2(.8,.7)],center,radius,color,width)
			_line([Vector2(0,-1),Vector2(0,-.76)],center,radius,color,width)
		"language_en":
			draw_arc(center,radius*.75,0,TAU,28,color,width,true)
			_line([Vector2(-.52,.6),Vector2(.46,-.8),Vector2(.75,-.65),Vector2(.08,.56),Vector2(-.52,.6)],center,radius,color,width)
			_line([Vector2(-.12,.06),Vector2(.58,-.35)],center,radius,color,width)
		"language_mixed":
			draw_arc(center-Vector2(radius*.25,0),radius*.56,-PI*.8,PI*.8,24,color,width,true)
			draw_arc(center+Vector2(radius*.25,0),radius*.56,PI*.2,PI*1.8,24,color,width,true)
			_line([Vector2(-.5,-.7),Vector2(.5,.7)],center,radius,color,width)
		"group_commuters":
			_line([Vector2(-.72,-.42),Vector2(.72,-.42),Vector2(.72,.55),Vector2(-.72,.55),Vector2(-.72,-.42)],center,radius,color,width)
			_line([Vector2(-.34,-.42),Vector2(-.34,-.77),Vector2(.34,-.77),Vector2(.34,-.42)],center,radius,color,width)
			_line([Vector2(-.72,-.02),Vector2(.72,-.02)],center,radius,color,width)
		"group_students":
			_line([Vector2(-.82,-.48),Vector2(0,-.26),Vector2(.82,-.48),Vector2(.82,.55),Vector2(0,.8),Vector2(-.82,.55),Vector2(-.82,-.48)],center,radius,color,width)
			_line([Vector2(0,-.26),Vector2(0,.8)],center,radius,color,width)
		"group_culture_fans":
			_line([Vector2(-.75,-.66),Vector2(.75,-.66),Vector2(.65,.2),Vector2(0,.75),Vector2(-.65,.2),Vector2(-.75,-.66)],center,radius,color,width)
			draw_arc(center+Vector2(0,radius*.03),radius*.32,.15,PI-.15,18,color,width,true)
			for x in [-.35,.35]: draw_circle(center+Vector2(x,-.32)*radius,radius*.09,color)
		"freedom":
			_line([Vector2(-.85,-.2),Vector2(-.34,.08),Vector2(0,-.52),Vector2(.34,.08),Vector2(.85,-.2)],center,radius,color,width)
			_line([Vector2(-.85,-.2),Vector2(-.26,.55),Vector2(0,.12),Vector2(.26,.55),Vector2(.85,-.2)],center,radius,color,width)
		"authority":
			_line([Vector2(-.6,.8),Vector2(-.6,-.35),Vector2(-.28,-.35),Vector2(-.28,-.76),Vector2(.28,-.76),Vector2(.28,-.35),Vector2(.6,-.35),Vector2(.6,.8),Vector2(-.6,.8)],center,radius,color,width)
			_line([Vector2(0,-.12),Vector2(0,.62)],center,radius,color,width)
		"equality":
			_line([Vector2(-.8,-.27),Vector2(.8,-.27)],center,radius,color,width)
			_line([Vector2(-.8,.27),Vector2(.8,.27)],center,radius,color,width)
			for x in [-.7,.7]: draw_arc(center+Vector2(x,0)*radius,radius*.8,-PI*.5,PI*.5,16,color,width*.6,true)
		"hierarchy":
			for row in 3:
				var half := .25+row*.25
				_line([Vector2(-half,-.7+row*.52),Vector2(half,-.7+row*.52)],center,radius,color,width)
			_line([Vector2(0,-.9),Vector2(0,.68)],center,radius,color,width)
		"sincere":
			_line([Vector2(0,.8),Vector2(-.72,.04),Vector2(-.6,-.55),Vector2(0,-.25),Vector2(.6,-.55),Vector2(.72,.04),Vector2(0,.8)],center,radius,color,width)
		"ironic":
			draw_arc(center,radius*.8,-PI*.86,PI*.84,28,color,width,true)
			_line([Vector2(-.62,.5),Vector2(.6,-.4),Vector2(.65,.1)],center,radius,color,width)
			for x in [-.3,.3]: draw_circle(center+Vector2(x,-.24)*radius,radius*.085,color)
		"support":
			_line([Vector2(-.8,.3),Vector2(-.3,.7),Vector2(.8,-.65)],center,radius,color,width*1.15)
			draw_arc(center,radius*.88,-PI*.65,PI*.9,26,color,width*.55,true)
		"opposition":
			draw_arc(center,radius*.8,0,TAU,28,color,width,true)
			_line([Vector2(-.58,.58),Vector2(.58,-.58)],center,radius,color,width)
		_:
			_line([Vector2(-.5,-.7),Vector2(.5,-.7),Vector2(.5,.7),Vector2(-.5,.7),Vector2(-.5,-.7)],center,radius,color,width)

func inspection() -> Dictionary:
	return {"definition":definition.duplicate(true),"metal_asset":METAL.resource_path,"kind":definition.get("kind",""),"native_icon":definition.get("id",""),"title_layout":"vertical" if definition.get("kind","")=="topic" else ("banner" if definition.get("kind","")=="group" else "circular"),"popup":false}
