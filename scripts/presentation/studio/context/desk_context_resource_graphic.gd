class_name DeskContextResourceGraphic
extends Control

const METAL := preload("res://assets/image/textures/studio/desk/metal_resources.png")
const PAPER := preload("res://assets/image/textures/studio/desk/blank_print_paper.png")
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
	var title := DeskLocalization.text(str(definition.get("title",definition.get("id",""))))
	var font := get_theme_default_font()
	if kind in ["language", "group"]:
		_draw_pencil_resource(kind, title)
		return
	if kind == "topic":
		var paper := Rect2(Vector2.ZERO,size)
		draw_rect(Rect2(Vector2(1,2),size),Color(0.18,0.17,0.13,.13))
		draw_texture_rect(PAPER,paper,false,Color("eee9d7"))
		_draw_caption(caption_layout(), Color("45493e"))
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

func _draw_pencil_resource(kind: String, _title: String) -> void:
	var caption := caption_layout()
	var edge: float = caption.pencil_edge
	var center: Vector2 = caption.pencil_center
	var ink := Color("53574a")
	if kind == "language":
		for pass_index in 2:
			var offset := Vector2(float(pass_index)*1.0,-float(pass_index)*0.6)
			draw_arc(center+offset,edge*.43+float(pass_index)*1.2,0.18,TAU-0.18,48,Color(ink,0.72 if pass_index==0 else 0.30),1.25,true)
	else:
		for pass_index in 2:
			var points := PackedVector2Array()
			for point: Vector2 in [Vector2(-.40,-.40),Vector2(.40,-.38),Vector2(.39,.39),Vector2(-.39,.40),Vector2(-.40,-.40)]:
				points.append(center+point*edge+Vector2(float(pass_index)*1.1,-float(pass_index)*.7))
			draw_polyline(points,Color(ink,.72 if pass_index == 0 else .28),1.25,true)
	_icon(center,edge*.28,ink,1.25)
	_draw_caption(caption, ink)

func _draw_caption(layout: Dictionary, ink: Color) -> void:
	for line: Dictionary in layout.get("lines", []):
		draw_string(get_theme_default_font(), line.baseline, line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(line.font_size), ink)

func caption_layout() -> Dictionary:
	var title := DeskLocalization.text(str(definition.get("title",definition.get("id",""))))
	var kind := str(definition.get("kind",""))
	var font := get_theme_default_font()
	if kind == "topic":
		var result := fit_text(font, "# " + title, Rect2(Vector2(10,1),(size-Vector2(20,2)).max(Vector2.ZERO)), clampi(int(size.y*.48),12,19), 12, 2)
		result.full_text = title
		return result
	var label := title.split(" · ")[0]
	var caption_height := font.get_ascent(14) + font.get_descent(14)
	if font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x > maxf(0,size.x-4):
		caption_height = (font.get_ascent(12)+font.get_descent(12))*2+2
	caption_height = minf(caption_height,maxf(0,size.y-12))
	var area := Rect2(Vector2(2,maxf(0,size.y-caption_height-2)),Vector2(maxf(0,size.x-4),caption_height))
	var result := fit_text(font,label,area,14,12,2)
	result.full_text = title
	# Keep the pencil mark above its caption, including in narrow two-slot layouts.
	result.pencil_edge = maxf(8,minf(size.x,area.position.y-4))
	result.pencil_center = Vector2(size.x*.5,float(result.pencil_edge)*.5)
	return result

static func fit_text(font: Font, text: String, area: Rect2, preferred: int = 14, minimum: int = 12, maximum_lines: int = 2) -> Dictionary:
	var clean := " ".join(text.replace("\r"," ").replace("\n"," ").replace("\t"," ").split(" ",false))
	var selected := minimum
	var wrapped: Dictionary = {}
	for fs in range(maxi(minimum,preferred),minimum-1,-1):
		var height := font.get_ascent(fs)+font.get_descent(fs)
		var capacity := mini(maximum_lines,maxi(0,floori(area.size.y/maxf(1,height))))
		var candidate := _wrap_text(font,clean,fs,area.size.x,capacity)
		selected = fs
		wrapped = candidate
		if not bool(candidate.truncated): break
	var line_height := font.get_ascent(selected)+font.get_descent(selected)
	var strings: Array = wrapped.get("text",[])
	var top := area.position.y+maxf(0,(area.size.y-line_height*strings.size())*.5)
	var lines: Array[Dictionary] = []
	for value: String in strings:
		var width := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,selected).x
		var rect := Rect2(Vector2(area.get_center().x-width*.5,top),Vector2(width,line_height))
		lines.append({"text":value,"font_size":selected,"rect":rect,"baseline":rect.position+Vector2(0,font.get_ascent(selected))})
		top += line_height
	return {"full_text":text,"area":area,"lines":lines,"font_size":selected,"truncated":bool(wrapped.get("truncated",not clean.is_empty()))}

static func _wrap_text(font: Font, text: String, fs: int, width: float, count: int) -> Dictionary:
	var result: Array[String] = []
	var rest := text
	var omitted := false
	while not rest.is_empty() and result.size() < count and width > 0:
		var length := _prefix(font,rest,fs,width)
		if length <= 0: break
		if _inside_english_word(rest,length):
			var space := rest.left(length).rfind(" ")
			if space > 0:
				length = space
			else:
				# A word wider than the line gets an explicit ellipsis, never an orphan suffix.
				var word_end := rest.find(" ")
				if word_end < 0: word_end = rest.length()
				result.append(_ellipsis(font,rest.left(word_end),fs,width))
				rest = rest.substr(word_end).strip_edges()
				omitted = true
				continue
		var row := rest.left(length).strip_edges()
		rest = rest.substr(length).strip_edges()
		if result.size()+1 == count and not rest.is_empty():
			row = _ellipsis(font,row,fs,width)
			omitted = true
		if not row.is_empty(): result.append(row)
	return {"text":result,"truncated":omitted or not rest.is_empty()}

static func _ellipsis(font: Font, text: String, fs: int, width: float) -> String:
	var room := width-font.get_string_size("…",HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x
	if room < 0: return ""
	var length := _prefix(font,text,fs,room)
	if _inside_english_word(text,length):
		var space := text.left(length).rfind(" ")
		if space > 0: length = space
	return text.left(length).strip_edges()+"…"

static func _inside_english_word(text: String, index: int) -> bool:
	if index <= 0 or index >= text.length(): return false
	return _english_letter(text.unicode_at(index-1)) and _english_letter(text.unicode_at(index))

static func _english_letter(code: int) -> bool:
	return code >= 65 and code <= 90 or code >= 97 and code <= 122

static func _prefix(font: Font, text: String, fs: int, width: float) -> int:
	var low := 0
	var high := text.length()
	while low < high:
		var middle := (low+high+1)/2
		if font.get_string_size(text.left(middle),HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x <= width: low = middle
		else: high = middle-1
	return low

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
	var kind := str(definition.get("kind",""))
	return {"definition":definition.duplicate(true),"metal_asset":METAL.resource_path,"kind":kind,"native_icon":definition.get("id",""),"title_layout":"pencil_caption" if kind in ["language","group"] else ("horizontal" if kind=="topic" else "circular"),"caption":caption_layout() if kind in ["language","group","topic"] else {},"popup":false,"visual_style":"pencil" if kind in ["language","group"] else ("paper_strip" if kind=="topic" else "metal_token"),"is_physical_token":kind in ["stance_token","pragmatic_token"],"pin_texture":"","pin_source_region":Rect2()}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		queue_redraw()
