class_name DeskEnvironment
extends Control

const DEFAULT_DESK := Rect2(-26, -32, 1652, 964)
const SURROUND := Rect2(-4000, -3000, 9600, 6900)
const EDGE_DEPTH := 29.0
const FLOOR_SHADER := preload("res://shaders/studio/desk_room_floor.gdshader")
const PAPER_TEXTURE := preload("res://assets/image/textures/studio/desk/design_print_paper.png")
const NOTE_TEXTURE := preload("res://assets/image/textures/studio/desk/ruled_note.png")

var _surface: TextureRect
var _desk_rect := DEFAULT_DESK
var _floor: ColorRect
var _clutter: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	z_index = -10
	_floor = ColorRect.new()
	_floor.name = "RoomFloor"
	_floor.position = SURROUND.position
	_floor.size = SURROUND.size
	_floor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor.z_index = -2
	var material := ShaderMaterial.new()
	material.shader = FLOOR_SHADER
	material.set_shader_parameter("surface_size", SURROUND.size)
	_floor.material = material
	add_child(_floor)
	_build_clutter()
	queue_redraw()


# The tabletop texture ends at this world-space rectangle. Camera framing never
# expands the wood to cover areas beyond its physical edge.
func configure(surface: TextureRect, desk_rect: Rect2 = DEFAULT_DESK) -> void:
	_surface = surface
	if _surface.get_parent() != self:
		_surface.reparent(self, false)
	_surface.z_index = 0
	layout_area(desk_rect)


func layout_area(desk_rect: Rect2 = DEFAULT_DESK) -> void:
	_desk_rect = desk_rect
	if is_instance_valid(_surface):
		_surface.position = desk_rect.position
		_surface.size = desk_rect.size
		if _surface.material is ShaderMaterial:
			_surface.material.set_shader_parameter("surface_size", desk_rect.size)
	queue_redraw()


func _paper(id: String, rect: Rect2, angle: float, tint: Color, texture: Texture2D) -> void:
	var shadow := Polygon2D.new()
	shadow.name = id + "Shadow"
	shadow.polygon = PackedVector2Array([Vector2.ZERO, Vector2(rect.size.x, 0), rect.size, Vector2(0, rect.size.y)])
	shadow.color = Color(0.04, 0.045, 0.035, 0.24)
	shadow.position = rect.position + Vector2(4, 6)
	shadow.rotation = angle
	shadow.z_index = -1
	add_child(shadow)
	var paper := TextureRect.new()
	paper.name = id
	paper.texture = texture
	paper.position = rect.position
	paper.size = rect.size
	paper.rotation = angle
	paper.modulate = tint
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.z_index = -1
	add_child(paper)
	_clutter.append({"id":id, "rect":rect, "angle":angle, "texture":texture.resource_path})


func _build_clutter() -> void:
	# These are room props, not spare resources or interactive inventory.
	_paper("LooseProofBack", Rect2(-202, 154, 125, 174), -0.19, Color("c2bda7"), PAPER_TEXTURE)
	_paper("LooseProofFront", Rect2(-187, 168, 120, 164), 0.08, Color("e0d5b8"), NOTE_TEXTURE)
	_paper("RightProofBack", Rect2(1694, 566, 149, 202), 0.18, Color("bfb49b"), PAPER_TEXTURE)
	_paper("RightProofFront", Rect2(1686, 575, 140, 191), -0.07, Color("d4c5a7"), NOTE_TEXTURE)
	_paper("DiscardedLowerProof", Rect2(213, 1005, 156, 194), -0.34, Color("bfb8a0"), PAPER_TEXTURE)
	_paper("FoldedUpperNote", Rect2(1114, -226, 162, 103), 0.18, Color("b4b29d"), NOTE_TEXTURE)


func _draw() -> void:
	_draw_room_props()
	var r := _desk_rect
	var right := r.end.x
	var bottom := r.end.y
	# Layered contact shadows stay outside the wood, including during rotation.
	for index in range(12, 0, -1):
		var spread := float(index) * 3.0
		draw_rect(Rect2(r.position + Vector2(-spread, EDGE_DEPTH * 0.5), r.size + Vector2(spread * 2.0, EDGE_DEPTH + spread)), Color(0.025, 0.025, 0.018, 0.012))
	var front := PackedVector2Array([Vector2(r.position.x, bottom - 1), Vector2(right, bottom - 1), Vector2(right + 8, bottom + EDGE_DEPTH), Vector2(r.position.x + 8, bottom + EDGE_DEPTH)])
	draw_colored_polygon(front, Color("4d4030"))
	var side := PackedVector2Array([Vector2(right - 1, r.position.y), Vector2(right + 8, r.position.y + EDGE_DEPTH), Vector2(right + 8, bottom + EDGE_DEPTH), Vector2(right - 1, bottom)])
	draw_colored_polygon(side, Color("3b3228"))
	for index in 10:
		var y := bottom + 2.0 + float(index) * 2.4
		var shade := Color("68553d") if index % 3 == 0 else Color("42382c")
		shade.a = 0.52
		draw_line(Vector2(r.position.x + 4, y), Vector2(right + 5, y + sin(float(index) * 1.7) * 0.7), shade, 0.8, true)
	draw_line(Vector2(r.position.x, bottom), Vector2(right, bottom), Color("a18a67"), 1.6, true)
	draw_line(Vector2(right, r.position.y), Vector2(right, bottom), Color("a18a67"), 1.1, true)
	for x in [r.position.x + 75.0, right - 76.0]:
		var point := Vector2(x, bottom + 15)
		draw_circle(point + Vector2(1, 1), 2.2, Color("2d2921"), true, -1, true)
		draw_line(point + Vector2(-1, -0.4), point + Vector2(1, 0.4), Color("857457"), 0.7, true)


func _draw_room_props() -> void:
	# A partly opened carton and a low stool frame the desk without competing
	# with the working paper. Their silhouettes are outside the tabletop.
	var box := Rect2(-281, 515, 177, 182)
	draw_rect(Rect2(box.position + Vector2(7, 12), box.size + Vector2(12, 10)), Color(0.03, 0.035, 0.025, 0.25))
	draw_colored_polygon(PackedVector2Array([box.position, box.position + Vector2(box.size.x, 14), box.end, box.position + Vector2(0, box.size.y - 17)]), Color("766b50"))
	draw_colored_polygon(PackedVector2Array([box.position + Vector2(8, 8), box.position + Vector2(161, 22), box.position + Vector2(162, 124), box.position + Vector2(10, 112)]), Color("302d24"))
	draw_colored_polygon(PackedVector2Array([box.position + Vector2(0, 88), box.position + Vector2(84, 110), box.position + Vector2(80, 190), box.position + Vector2(-21, 162)]), Color("94805b"))
	draw_colored_polygon(PackedVector2Array([box.position + Vector2(87, 111), box.position + Vector2(177, 91), box.position + Vector2(200, 159), box.position + Vector2(103, 193)]), Color("897654"))
	for index in 9:
		var x := box.position.x + 9 + float(index) * 18
		draw_line(Vector2(x, box.position.y + 123), Vector2(x - 11, box.end.y - 5), Color(0.31, 0.27, 0.18, 0.20), 0.7, true)
	var stool := Vector2(917, 1126)
	draw_circle(stool + Vector2(10, 14), 82, Color(0.025, 0.03, 0.024, 0.22), true, -1, true)
	for x in [-52.0, 52.0]:
		draw_line(stool + Vector2(x, 14), stool + Vector2(x * 1.16, 119), Color("36392f"), 10, true)
		draw_line(stool + Vector2(x - 2, 14), stool + Vector2(x * 1.16 - 2, 119), Color("5c5d4a"), 2, true)
	draw_circle(stool, 76, Color("3e4135"), true, -1, true)
	draw_circle(stool - Vector2(0, 5), 73, Color("77715a"), true, -1, true)
	draw_arc(stool - Vector2(0, 5), 69, 0.2, PI * 1.8, 96, Color("948973"), 1.5, true)


func inspection() -> Dictionary:
	return {"component":"finite_desk_and_room", "desk_rect":_desk_rect, "desk_edge_depth":EDGE_DEPTH, "surface_rect":Rect2(_surface.position, _surface.size) if is_instance_valid(_surface) else Rect2(), "surface_world_bounds":_surface.get_global_transform() * Rect2(Vector2.ZERO, _surface.size) if is_instance_valid(_surface) else Rect2(), "wood_repeats_outside_desk":false, "room_props":_clutter.duplicate(true), "interactive":false}
