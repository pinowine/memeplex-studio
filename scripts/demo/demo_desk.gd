extends Control

const ShadowObject := preload("res://scripts/demo/desk_object_shadow.gd")
const LogPrinter := preload("res://scripts/demo/desk_log_printer.gd")
const MemeMonitor := preload("res://scripts/demo/desk_meme_monitor.gd")
const PropInteraction := preload("res://scripts/demo/desk_prop_interaction.gd")
const RuledContacts := preload("res://scripts/demo/desk_ruled_contacts.gd")
const SpeedStrip := preload("res://scripts/demo/desk_speed_strip.gd")
const MaterialCards := preload("res://scripts/demo/desk_material_cards.gd")
const FaxStation := preload("res://scripts/demo/desk_fax_station.gd")
const PaperStyle := preload("res://scripts/demo/desk_paper_style.gd")
const FixedInk := preload("res://shaders/desk_fixed_light.gdshader")
const TornHover := preload("res://shaders/desk_torn_hover.gdshader")
const PRINTER_CROP := Rect2(90, 45, 1130, 930)
const PRINTER_SLOT := Rect2(334, 932, 646, 4)
const FAX_SLOT := Rect2(398, 1004, 688, 4)
const LAYOUT_PATH := "res://demo_saves/desk_layout.json"
@export var presentation: DeskPresentation = preload("res://content/print/desk_presentation.tres")

var _page: Node2D
var _art: Dictionary = {}
var _textures: Dictionary = {}
var _shadows: Dictionary = {}
var _hover: Dictionary = {}
var _paper: StyleBoxTexture
var _stack: Control
var _stack_rect := Rect2()
var _active_sheet := "edit"
var _clock: Control
var _clock_presenter: RefCounted
var _country_layer: CanvasLayer
var _printer: DeskLogPrinter
var _monitor: DeskMemeMonitor
var _fax: DeskFaxStation
var _archive: Control
var _speed_strip: DeskSpeedStrip
var _token_boxes: Dictionary = {}
var _material_cards: DeskMaterialCards
var _context_layer_items: Dictionary = {}
var _receipt_layer: CanvasLayer
var _event_archive: Dictionary = {}
var _pending_archive_event: Dictionary = {}
var _dependent_updates := 0
var _props: DeskPropInteraction
var _light: Node2D
var _wires: Dictionary = {}
var _book_contacts: Control
var _placed := false
var _registered := false
var _layout_dirty := false
var _restoring_placement := false
var _layout_error := ""
var _journal: Array = []
var _journal_known: Dictionary = {}
var _journal_seed := -1
var _journal_hour := 0
var _status_text := ""
var _outlet := Vector2.ZERO
var _outlet_width := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_priority = 30
	for id in ["desk_surface", "folder", "paper_texture", "blank_print_paper"]:
		_textures[id] = load("res://assets/desk/v1/" + id + ".png") as Texture2D
	for id in ["fax_downward", "crt_clean", "phonebook", "stamp_prop", "stamp_67", "landscape_paper", "portrait_67", "map_print_paper", "design_print_paper", "map_square_note", "design_square_note"]:
		_textures[id] = load("res://assets/desk/v3/" + id + ".png") as Texture2D
	_textures.fax = _textures.fax_downward
	_textures.crt = _textures.crt_clean
	_textures.stamp = _textures.stamp_prop
	_textures.folder = load("res://assets/desk/v4/folder_closed.png")
	_textures.folder_open = load("res://assets/desk/v4/folder_open.png")
	_textures.note = load("res://assets/desk/v2/ruled_note.png")
	_textures.tape = load("res://assets/desk/v2/clear_tape.png")
	var printer := AtlasTexture.new()
	printer.atlas = load("res://assets/desk/v2/receipt_printer.png")
	printer.region = PRINTER_CROP
	_textures.printer = printer
	_art.desk_surface = _image("DeskSurface", _textures.desk_surface, self)
	resized.connect(_layout)


func _image(id: String, texture: Texture2D, parent: Node) -> TextureRect:
	var image := TextureRect.new()
	image.name = id
	image.texture = texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(image)
	return image


func _shadow(id: String, texture: Texture2D, parent: Node) -> Control:
	var shade := ShadowObject.new()
	shade.name = id
	parent.add_child(shade)
	shade.configure(texture)
	return shade


func configure(page: Node2D) -> void:
	_page = page
	_light = Node2D.new()
	_light.name = "FixedDeskLight"
	_light.set_meta("height", 380.0)
	add_child(_light)
	_paper = StyleBoxTexture.new()
	_paper.texture = _textures.design_print_paper
	_paper.set_texture_margin_all(22)
	_paper.set_content_margin_all(22)
	for panel: PanelContainer in _panels(page.hud):
		panel.add_theme_stylebox_override("panel", _paper)
		_add_grain(panel)
		PaperStyle.apply_buttons(panel)
	page.tools.add_theme_stylebox_override("panel", _paper)
	PaperStyle.apply_buttons(page.tools)
	page.tools.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.tools.offset_left = 32
	page.tools.offset_top = 24
	page.tools.offset_right = -32
	page.tools.offset_bottom = -24
	var workbench: Control = page.hud.get_node("%Workbench")
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(25)
	empty.set_content_margin(SIDE_TOP, 85)
	workbench.add_theme_stylebox_override("panel", empty)
	workbench.get_node("Column/Toolbar/Heading").text = "模因设计 / 印前稿"
	for id in ["Fullscreen", "SelectCountry", "Purchase"]: page.hud.get_node("%" + id).hide()
	page.hud.get_node("%SettingsMenu").minimum_size_changed.connect(_fit_settings)
	page.hud.get_node("%CodexPanel").minimum_size_changed.connect(_fit_codex)
	_country_layer = CanvasLayer.new()
	_country_layer.name = "CountryFileLayer"
	_country_layer.layer = 31
	page.atlas.add_child(_country_layer)
	page.atlas.drawer.reparent(_country_layer, false)
	page.atlas.setup_note.reparent(_country_layer, false)
	_stack = load("res://scripts/demo/desk_sheet_stack.gd").new()
	_stack.name = "PaperStack"
	add_child(_stack)
	_stack.configure(page.atlas.map_input, page.atlas.get_node("%MapFinish"), page.spread, workbench,
		{"paper":_textures.map_print_paper, "map_paper":_textures.map_print_paper, "design_paper":_textures.design_print_paper,
		"edit_paper":_textures.design_print_paper,"cultivate_paper":_textures.blank_print_paper,"spread_paper":_textures.landscape_paper,
		"map_note":_textures.map_square_note,"design_note":_textures.design_square_note})
	_stack.switch_started.connect(_sheet_started)
	_stack.switch_completed.connect(_sheet_settled)
	_clock_presenter = load("res://scripts/demo/desk_clock_presenter.gd").new()
	_clock = _clock_presenter.configure(page.atlas)
	_art.clock = _clock_presenter.image_node()
	_art.clock.material = _screen_ink(_art.clock.texture)
	_shadows.clock = _shadow("ClockShadow", _art.clock.texture, _art.clock.get_parent())
	_shadows.clock.z_index = -2
	for id in ["phonebook", "stamp", "folder", "crt", "printer", "fax"]:
		_shadows[id] = _shadow(id.to_pascal_case() + "Shadow", _textures[id], page.hud)
		_art[id] = _image(id.to_pascal_case(), _textures[id], page.hud)
		_art[id].stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_art[id].material = _screen_ink(_textures[id])
		var depth: int = {"phonebook":1, "stamp":24, "folder":4, "crt":5, "fax":8, "printer":10}[id]
		_shadows[id].z_index = depth - 1
		_art[id].z_index = depth
	_book_contacts = RuledContacts.new()
	_book_contacts.name = "CollectedPhones"
	_book_contacts.first_rule = 9
	_art.phonebook.add_child(_book_contacts)
	_speed_strip = SpeedStrip.new()
	_speed_strip.name = "IndependentSpeedStrip"
	_speed_strip.theme = page.hud.theme
	_speed_strip.z_index = 7
	page.hud.add_child(_speed_strip)
	_speed_strip.speed_requested.connect(page._set_speed)
	_art.speed = _speed_strip.background_node()
	_art.speed.material = _screen_ink(_art.speed.texture)
	_shadows.speed = _shadow("SpeedStripShadow", _art.speed.texture, _speed_strip)
	_shadows.speed.z_index = -1
	for layer in ["stance","pragmatic"]:
		var box := load("res://scripts/demo/desk_token_box.gd").new() as Control
		box.name = layer.to_pascal_case()+"TokenBox"
		box.z_index=16
		page.hud.add_child(box)
		box.configure(layer,page.simulation.design_state.rules)
		_token_boxes[layer]=box
		var prop_id: String = "tokens/"+layer
		_art[prop_id]=box.background_node()
		_art[prop_id].material=_screen_ink(_art[prop_id].texture)
		_shadows[prop_id]=_shadow(layer.to_pascal_case()+"BoxShadow",_art[prop_id].texture,box)
		_shadows[prop_id].z_index=-1
	_printer = LogPrinter.new()
	_printer.name = "LogPrinter"
	_printer.font_size = 13
	_printer.hierarchical_typography = true
	_printer.row_height = 21
	_printer.paper_padding = 10
	_printer.paper_region_rect = Rect2(52, 76, 982, 1292)
	_printer.chars_per_second = presentation.log_chars_per_second
	_printer.feed_speed = presentation.log_feed_speed
	_printer.wheel_scroll_enabled = true
	_receipt_layer = CanvasLayer.new()
	_receipt_layer.name = "BottomReceiptLayer"
	_receipt_layer.layer = 1
	add_child(_receipt_layer)
	_printer.theme = page.hud.theme
	_printer.z_index = 0
	_receipt_layer.add_child(_printer)
	_printer.configure(_textures.blank_print_paper, _textures.paper_texture)
	_printer.event_requested.connect(_open_event_archive)
	_monitor = MemeMonitor.new()
	_monitor.name = "MemeMonitor"
	_monitor.font_size = 11
	_monitor.screen_padding = 6
	_monitor.curve_height = 35
	_monitor.z_index = 6
	page.hud.add_child(_monitor)
	_fax = FaxStation.new()
	_fax.name = "FaxStation"
	_fax.z_index = 19
	page.hud.add_child(_fax)
	_fax.configure({"machine":_textures.fax,"portrait_67":_textures.portrait_67,"stamp":_textures.stamp_67,
		"phonebook":_textures.phonebook,"stamp_prop":_textures.stamp}, page.hud.theme, {"source_mouth":FAX_SLOT,"page_keyboard_shortcuts":true})
	_fax.bind_machine(_art.fax, FAX_SLOT)
	_fax.read_completed.connect(page._read_intelligence)
	_fax.material_requested.connect(_request_event_material)
	_fax.focus_changed.connect(_fax_focus_changed)
	_archive = load("res://scripts/demo/desk_archive_browser.gd").new()
	_archive.name = "DiscoveredArchive"
	page.hud.add_child(_archive)
	_archive.configure({"closed":_textures.folder,"open":_textures.folder_open,"paper":_textures.design_print_paper,"bookgrain":_textures.paper_texture}, page.hud.theme)
	_archive.bind_folder(_art.folder)
	_archive.focus_changed.connect(_archive_focus_changed)
	_archive.event_requested.connect(_archive_event_requested)
	_props = PropInteraction.new()
	_props.name = "DeskInteractions"
	add_child(_props)
	_props.clicked.connect(_prop_clicked)
	_props.moved.connect(_prop_moved)
	_props.hovered.connect(_prop_hovered)
	# Reverse tree input order gives desk props first refusal before fax focus.
	_props.reparent(page.hud)
	for id in ["fax", "printer"]:
		var cable := Line2D.new()
		cable.name = "TelephoneCable" if id == "fax" else "DataCable"
		cable.width = 5.0
		cable.default_color = Color("292d25")
		cable.antialiased = true
		cable.z_index = 0
		page.hud.add_child(cable)
		_wires[id] = cable
	_page.hud.configure_desk(Rect2(1, 1, 1, 1), self)
	_layout()
	_register_props()
	_restore_placement()
	presentation.changed.connect(_update_prop_dependents)
	_update_contacts()
	_material_cards = MaterialCards.new()
	_material_cards.name = "TabletopMaterials"
	_material_cards.z_index = 20
	page.hud.add_child(_material_cards)
	page.hud.move_child(_material_cards, 0)
	_material_cards.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material_cards.configure(page.simulation.design_state.rules, _light, _screen_ink(_textures.blank_print_paper))
	_material_cards.set_spawn_area(Rect2(_stack_rect.end.x+10,350,maxf(96,size.x-_stack_rect.end.x-22),maxf(140,size.y-362)))
	_material_cards.item_clicked.connect(_inspect_material)
	_material_cards.item_dropped.connect(_drop_material)
	_material_cards.release_module.connect(_unclip_module)
	page.hud.material_tabletop_requested.connect(_material_cards.request_item)
	var editor: Control = page.hud.design_workbench()
	if editor.has_signal("module_paper_detached"):
		editor.module_paper_detached.connect(_module_paper_detached)
	if editor.has_signal("context_layer_detached"):
		editor.context_layer_detached.connect(_place_context_layer)
	if editor.has_signal("context_resource_detached"):
		editor.context_resource_detached.connect(func(record: Dictionary,point: Vector2) -> void:
			_material_cards.place_existing_item(str(record.get("kind","")),str(record.get("id","")),point))


func _screen_ink(texture: Texture2D) -> ShaderMaterial:
	var ink := ShaderMaterial.new()
	ink.shader = FixedInk
	for field in ["dot_pitch", "ink_strength", "ink_color", "tint_mix", "posterize_levels"]:
		ink.set_shader_parameter(field, presentation.get(field))
	ink.set_shader_parameter("light_height", 380.0)
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		ink.set_shader_parameter("source_uv_rect", Vector4(atlas.region.position.x / atlas.atlas.get_width(),
			atlas.region.position.y / atlas.atlas.get_height(), atlas.region.size.x / atlas.atlas.get_width(), atlas.region.size.y / atlas.atlas.get_height()))
	return ink


func _panels(parent: Node) -> Array[PanelContainer]:
	var result: Array[PanelContainer] = []
	for node in parent.find_children("*", "PanelContainer", true, false): result.append(node as PanelContainer)
	return result


func _add_grain(panel: PanelContainer) -> void:
	var grain := TextureRect.new()
	grain.name = "PaperGrain"
	grain.texture = _textures.paper_texture
	grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR = texture(TEXTURE, UV * 4.0) * COLOR; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	grain.material = material
	grain.modulate.a = 0.13
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wrapper := Control.new()
	wrapper.name = "PaperSurface"
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(wrapper)
	panel.move_child(wrapper, 0)
	wrapper.add_child(grain)
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _place(node: Control, rect: Rect2) -> void:
	node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	node.position = rect.position
	node.size = rect.size


func _layout() -> void:
	if _page == null or not is_node_ready(): return
	var view := get_viewport_rect().size
	_place(_art.desk_surface, Rect2(Vector2.ZERO, view))
	_light.position = Vector2(view.x * 0.35, -180)
	if not _placed:
		_prop(_art.fax, Rect2(10, -44, 300, 274), -0.067)
		_prop(_art.phonebook, Rect2(14, 47, 260, 186), -0.04)
		_prop(_art.folder, Rect2(570, -44, 250, 184), 0.065)
		_prop(_art.crt, Rect2(view.x - 455, -14, 225, 169), -0.04)
		_prop(_art.stamp, Rect2(275, 115, 90, 90), 0.09)
		_place(_clock, Rect2(326, 8, 216, 216))

		_placed = true
	_prop(_art.printer, Rect2(view.x - 236, -32, 280, 231), 0.022)
	_stack_rect = Rect2(64, 175, view.x - 276, view.y - 203)
	_stack.layout_area(_stack_rect)
	_layout_speed_strip()
	for index in 2:
		var layer: String = ["stance","pragmatic"][index]
		var box: Control = _token_boxes[layer]
		if not box.has_meta("desk_placed"):
			_place(box,Rect2(view.x-238+index*118,view.y-208,108,108))
			box.rotation=deg_to_rad(-3 if index==0 else 3)
			box.set_meta("desk_placed",true)
	_page.atlas.fit_map()
	_book_contacts.layout_book(Rect2(Vector2.ZERO,_art.phonebook.size))
	_place(_page.atlas.setup_note, Rect2(_stack_rect.position + Vector2(30, _stack_rect.size.y - 100), Vector2(_stack_rect.size.x - 60, 87)))
	_page.hud.configure_desk(_stack_rect, self)
	if _material_cards != null:
		_material_cards.set_spawn_area(Rect2(_stack_rect.end.x+10,350,maxf(96,view.x-_stack_rect.end.x-22),maxf(140,view.y-362)))
	_props.set_bounds(Rect2(-65, -92, view.x + 130, view.y + 150))
	_archive.layout_browser(Rect2(Vector2.ZERO, view))
	_update_prop_dependents()
	_fit_settings()
	_fit_codex()


func _prop(node: TextureRect, rect: Rect2, angle: float) -> void:
	_place(node, rect)
	node.pivot_offset = node.size * 0.5
	node.rotation = angle


func _layout_speed_strip() -> void:
	var world_tab: Control = _stack.tab_control("map")
	if world_tab == null: return
	var world_rect := world_tab.get_global_rect()
	_place(_speed_strip,Rect2(world_rect.position.x+7,world_rect.position.y-62,145.2,53.9))


func _layout_receipt(view: Vector2) -> void:
	var machine: TextureRect = _art.printer
	var fitted := ShadowObject.fit_rect(machine.texture.get_size(), machine.size, machine.stretch_mode)
	var factor := fitted.size.x / PRINTER_CROP.size.x
	var local := fitted.position + (PRINTER_SLOT.position - PRINTER_CROP.position) * factor
	_outlet = machine.get_global_transform() * local
	_outlet_width = PRINTER_SLOT.size.x * factor
	_printer.layout_area(Rect2(_outlet, Vector2(_outlet_width, view.y - _outlet.y + 24)))
	_printer.pivot_offset = Vector2.ZERO
	_printer.rotation = machine.rotation


func _layout_monitor() -> void:
	var machine: TextureRect = _art.crt
	var fitted := ShadowObject.fit_rect(machine.texture.get_size(), machine.size, machine.stretch_mode)
	var factor := fitted.size.x / machine.texture.get_width()
	var origin := machine.get_global_transform() * (fitted.position + Vector2(270, 206) * factor)
	_monitor.layout_screen(Rect2(origin, Vector2(908, 557) * factor))
	_monitor.pivot_offset = Vector2.ZERO
	_monitor.rotation = machine.rotation


func _update_prop_dependents() -> void:
	_dependent_updates += 1
	_layout_speed_strip()
	var view := get_viewport_rect().size
	_layout_receipt(view)
	_layout_monitor()
	_fax.layout_station(_art.fax.get_global_rect(), Rect2(Vector2.ZERO, view), FAX_SLOT)
	_wires.fax.points = PackedVector2Array([Vector2(84, -100), Vector2(74, -18), Vector2(35, 24), _art.fax.get_global_transform() * Vector2(20, 96)])
	_wires.printer.points = PackedVector2Array([Vector2(view.x + 80, -80), Vector2(view.x - 70, -19), _art.printer.get_global_transform() * Vector2(234, 68)])
	for id in _art:
		if _art[id].material is ShaderMaterial:
			_art[id].material.set_shader_parameter("light_position", _light.global_position)
	refresh_shadows()
	_update_hover_geometry()


func refresh_shadows(ids: Array = []) -> void:
	for id in (_shadows.keys() if ids.is_empty() else ids):
		var source: TextureRect = _art[id]
		var shade: Control = _shadows[id]
		var center := source.get_global_transform() * (source.size * 0.5)
		var distance := 1.6 if id == "speed" else presentation.shadow_offset.length()
		var direction := (center - _light.global_position).normalized() * distance
		shade.shadow_offset = source.get_global_transform().affine_inverse().basis_xform(direction)
		shade.shadow_blur = 1.2 if id == "speed" else presentation.shadow_blur
		shade.shadow_opacity = presentation.shadow_opacity
		shade.ao_radius = 1.5 if id == "speed" else presentation.ao_radius
		shade.ao_strength = presentation.ao_strength
		shade.shadow_color = presentation.shadow_color
		shade.sync_from(source)
		shade.visible = presentation.shadows_enabled and source.visible
		shade.apply_parameters()


func _register_props() -> void:
	if _registered: return
	_registered = true
	# Paper may overlap machines; only solid desk equipment blocks other machines.
	for id in ["phonebook", "folder", "crt", "clock", "speed", "printer", "fax", "stamp"]:
		var node: Control = _clock if id == "clock" else (_speed_strip if id == "speed" else _art[id])
		var hit := Rect2(Vector2.ZERO, node.size)
		if id == "fax": hit = Rect2(7, 17, 286, 225)
		if id == "printer": hit = Rect2(7, 9, 267, 217)
		if id == "crt": hit = Rect2(14, 9, 198, 155)
		_props.register_prop(id, node, hit, id in ["folder", "crt", "clock", "printer", "fax"], id not in ["printer", "fax", "speed"])
		var cores := {"clock":Rect2(38,41,140,146),"folder":Rect2(23,24,208,137),"crt":Rect2(30,30,174,130),
			"printer":Rect2(25,30,240,185),"fax":Rect2(25,36,265,168)}
		if cores.has(id): _props.set_collision_rect(id, cores[id])
		if id != "speed": _create_hover(id, _art[id])
	for layer in _token_boxes:
		var box: Control = _token_boxes[layer]
		_props.register_prop("tokens/"+str(layer),box,Rect2(Vector2.ZERO,box.size),false,true)
		_create_hover("tokens/"+str(layer),box.background_node())
	for id in ["map", "edit", "cultivate", "spread"]:
		var sheet: Control = _stack.sheet_node(id)
		var tab: Control = _stack.tab_node(id)
		_props.register_prop("sheet/" + id, sheet, Rect2(tab.position, tab.size), false, false)
		_create_hover("sheet/" + id, tab.get_node("Note"))


func _create_hover(id: String, source: TextureRect) -> void:
	var outline := _image("TornHover", source.texture, source.get_parent())
	outline.z_index = source.z_index - 1
	var material := ShaderMaterial.new()
	material.shader = TornHover
	var texture: Texture2D = source.texture
	var uv := Vector4(0, 0, 1, 1)
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		texture = atlas.atlas
		uv = Vector4(atlas.region.position.x / texture.get_width(), atlas.region.position.y / texture.get_height(),
			atlas.region.size.x / texture.get_width(), atlas.region.size.y / texture.get_height())
	material.set_shader_parameter("source_texture", texture)
	material.set_shader_parameter("source_uv_rect", uv)
	material.set_shader_parameter("band_width", 7.0)
	material.set_shader_parameter("padding", Vector2(10, 10))
	material.set_shader_parameter("rect_origin", Vector2(10, 10))
	outline.material = material
	outline.hide()
	_hover[id] = {"node":outline,"source":source}


func _update_hover_geometry() -> void:
	for id in _hover:
		_update_hover_item(_hover[id])


func _update_hover_item(item: Dictionary) -> void:
	var source: TextureRect = item.source
	var fitted := ShadowObject.fit_rect(source.texture.get_size(), source.size, source.stretch_mode)
	var outline: TextureRect = item.node
	_place(outline, Rect2(source.position + fitted.position - Vector2(10, 10), fitted.size + Vector2(20, 20)))
	outline.pivot_offset = source.pivot_offset - fitted.position + Vector2(10, 10)
	outline.rotation = source.rotation
	outline.scale = source.scale
	outline.material.set_shader_parameter("object_size", fitted.size)


func _prop_hovered(id: StringName) -> void:
	for key in _hover: _hover[key].node.visible = String(id) == key


func _prop_clicked(id: StringName) -> void:
	match String(id):
		"folder": _archive.focus()
		"fax": _fax.focus()
		"phonebook": _fax.focus()
		"stamp": _fax.arm_stamp()
		"sheet/map": select_sheet("map")
		"sheet/edit": select_sheet("edit")
		"sheet/cultivate": select_sheet("cultivate")
		"sheet/spread": select_sheet("spread")


func _prop_moved(id: StringName, _point: Vector2) -> void:
	_layout_dirty = not _restoring_placement
	# Moving one prop must not relayout stationary machines and their paper.
	if String(id) == "crt": _layout_monitor()
	if _shadows.has(String(id)): refresh_shadows([String(id)])
	if _hover.has(String(id)): _update_hover_item(_hover[String(id)])
	if String(id) == "stamp" and not _restoring_placement:
		_fax.stamp_at(_art.stamp.get_global_transform() * (_art.stamp.size * 0.5))


func _inspect_material(kind: String, id: String) -> void:
	if not _page.startup_ready(): return
	select_sheet("edit" if kind=="module" else "cultivate")
	var editor: Control = _page.hud.design_workbench()
	if editor.has_method("show_material"): editor.show_material(kind, id)


func _request_event_material(record: Dictionary, point: Vector2) -> void:
	if _material_cards == null or _fax.inspection().blocked:
		_fax.confirm_material_request(record, false)
		return
	_material_cards.remember_event_position(record, point)
	var errors: PackedStringArray = _page._request_event_material(record)
	if not errors.is_empty(): _material_cards.discard_event_position(record)
	_fax.confirm_material_request(record, errors.is_empty())

func _module_paper_detached(id: String, point: Vector2) -> void:
	# Reposition the existing detached paper without creating another item.
	if _material_cards != null: _material_cards.place_existing_item("module",id,point)


func _unclip_module(slot: int, _id: String) -> void:
	var editor: Control = _page.hud.design_workbench()
	editor._request("remove_module", {"slot":slot})


func _sync_module_papers() -> void:
	if _material_cards == null: return
	var editor: Control = _page.hud.design_workbench()
	var slots: Array = editor._design.get("module_slots", [])
	for slot in slots.size():
		var id := str(slots[slot])
		if not id.is_empty():
			_material_cards.clamp_module(id,slot,editor.module_clip_parent(slot),Vector2(4,15))


func _drop_material(kind: String, id: String, point: Vector2) -> void:
	if _active_sheet == "map" or not _page.startup_ready(): return
	var editor: Control = _page.hud.design_workbench()
	if editor.has_method("accept_tabletop_item") and editor.accept_tabletop_item(kind, id, point):
		_sync_staged_materials()
		if kind == "module": _sync_module_papers()
		else: _material_cards.return_to_inventory(kind, id)


func _fax_focus_changed(focused: bool) -> void:
	_sync_reader_blocks()
	_page.atlas.set_speed(0 if focused or _page.hud.get_node("%Workbench").visible else _page.simulation.speed)
	if not focused: _page._sync_setup()


func _archive_focus_changed(focused: bool) -> void:
	_sync_reader_blocks()
	_page.atlas.set_speed(0 if focused or _page._interface_paused() or _page.hud.get_node("%Workbench").visible else _page.simulation.speed)
	if not focused:
		_update_prop_dependents()
		if not _pending_archive_event.is_empty():
			var event := _pending_archive_event
			_pending_archive_event = {}
			_fax.view_archived_event(event)
		_page._sync_setup()


func _open_event_archive(instance_id: String) -> void:
	if not _event_archive.has(instance_id) or _page.hud.modal_visible() or _page.tools.visible or _fax.get("_focused"): return
	_archive.select_tab("events")
	_archive.select_item(instance_id)
	_archive.focus()


func _archive_event_requested(event: Dictionary) -> void:
	# The archive already shows full details while an unread fax remains pending.
	if not (_fax.get("_active") as Dictionary).is_empty():
		_archive.set_notice("当前传真尚未收阅；完整历史已显示在右页，先盖戳再打开情报纸。")
		return
	_pending_archive_event = event.duplicate(true)
	if not _archive.close(): _pending_archive_event = {}


func _update_contacts() -> void:
	var contacts: Array = _fax.get("_contacts")
	_book_contacts.set_contacts(contacts)


func _fit_settings() -> void:
	if _page == null: return
	var view := get_viewport_rect().size
	_place(_page.hud.get_node("%SettingsMenu"), Rect2(view.x * 0.5 - 215, view.y * 0.5 - 295, 430, 590))


func _fit_codex() -> void:
	if _page != null and _stack_rect.has_area(): _place(_page.hud.get_node("%CodexPanel"), _stack_rect)


func clock_rect() -> Rect2:
	return _clock.get_global_rect() if _clock != null else Rect2()


func interaction_paused() -> bool:
	return _stack != null and (_stack.is_switching() or (_fax != null and bool(_fax.get("_focused"))) or (_archive != null and bool(_archive.get("_focused"))))


func _sync_reader_blocks() -> void:
	var blocked: bool = _page.hud.modal_visible() or _page.tools.visible or _stack.is_switching() or (_page._shell != null and _page._shell.blocks_input())
	# Native fax input runs before archive GUI input; keep the readers exclusive.
	_fax.set_interaction_blocked(blocked or bool(_archive.get("_focused")))
	_archive.set_interaction_blocked(blocked or bool(_fax.get("_focused")))


func select_sheet(id: String) -> void:
	if _page != null and _page.has_method("startup_ready") and not _page.startup_ready():
		_page.open_startup_call()
		return
	if _page != null and _page._shell != null and _page._shell.blocks_input(): return
	if _page == null or _page.hud.modal_visible() or _page.tools.visible or _fax.inspection().focused: return
	if _stack.is_switching(): return
	_page.hud.show_sheet(id)
	if _active_sheet == id and not _stack.is_switching(): _page._tutorial_observe("sheet_selected", {"id":id})


func sheet_changed(id: String) -> void:
	if id in ["meme", "design"]: id = "edit"
	if id not in ["map", "edit", "cultivate", "spread"]: return
	if _stack != null: _stack.select_sheet(id)


func _sheet_started(_id: String) -> void:
	_page.atlas.set_speed(0)
	if _props != null: _props.cancel_drag()


func _sheet_settled(id: String) -> void:
	_active_sheet = id
	_page._tutorial_observe("sheet_selected", {"id":id})
	_update_prop_dependents()
	_page.atlas.map_input.visible = _active_sheet == "map"
	_page.atlas.get_node("%MapFinish").visible = _active_sheet == "map"
	_page.spread.visible = _active_sheet == "map"
	_page.atlas.fit_map()
	_sync_staged_materials()
	_page._sync_setup()
	_page.atlas.set_speed(0 if _active_sheet != "map" or _page._interface_paused() else _page.simulation.speed)


func receive_event(event: Dictionary) -> void:
	_pending_archive_event = {}
	_fax.receive_event(event)
	_update_contacts()


func event_ready() -> bool:
	return _fax != null and _fax.inspection().event_state == "ready"


func _restore_placement() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if not parsed is Dictionary or int(parsed.get("version",0)) not in [1,2,3] or not parsed.get("placements") is Dictionary:
		_layout_error = "Invalid desk layout; current layout unchanged."
		return
	var positions: Dictionary = parsed.placements.duplicate(true)
	for key in positions.keys():
		if str(key).begins_with("sheet/") or str(key) == "speed": positions.erase(key)
	var previous := _props.placements()
	_restoring_placement = true
	var errors := _props.apply_placements(positions)
	if errors.is_empty() and int(parsed.get("version",0)) in [2,3]:
		if not parsed.get("paper_offsets") is Dictionary:
			errors.append("Invalid neutral paper offsets")
		else:
			errors.append_array(_stack.import_offsets(parsed.paper_offsets))
		if not errors.is_empty(): _props.apply_placements(previous)
	elif errors.is_empty():
		var offsets := _legacy_paper_offsets(parsed.placements)
		if not offsets.is_empty(): errors.append_array(_stack.import_offsets(offsets))
		if not errors.is_empty(): _props.apply_placements(previous)
	_restoring_placement = false
	_layout_error = "; ".join(errors)
	_layout_dirty = false
	_update_prop_dependents()


func _legacy_paper_offsets(positions: Dictionary) -> Dictionary:
	# Version 1 did not record the active sheet. Only an unchanged front identifies it.
	var origin := Vector2(64, 255)
	var points := {}
	for id in ["map", "design"]:
		var value: Variant = positions.get("sheet/" + id)
		if not value is Dictionary or not value.get("x") is float or not value.get("y") is float: return {}
		points[id] = Vector2(float(value.x), float(value.y))
	var active := ""
	if points.design.is_equal_approx(origin): active = "design"
	elif points.map.is_equal_approx(origin): active = "map"
	else: return {}
	var result := {}
	for id in points:
		var offset: Vector2 = points[id] - origin - (Vector2.ZERO if id == active else Vector2(-24, 9))
		result["meme" if id == "design" else id] = {"x":offset.x,"y":offset.y}
	return result


func _save_placement() -> void:
	var path := ProjectSettings.globalize_path(LAYOUT_PATH)
	var directory := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		_layout_error = "Desk layout directory: " + error_string(error)
		return
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		_layout_error = "Desk layout write: " + error_string(FileAccess.get_open_error())
		return
	var positions := _props.placements()
	for key in positions.keys():
		if str(key).begins_with("sheet/") or str(key) == "speed": positions.erase(key)
	file.store_string(JSON.stringify({"version":3,"placements":positions,"paper_offsets":_stack.export_offsets()}, "\t"))
	file.flush()
	file.close()
	error = DirAccess.rename_absolute(temporary, path)
	_layout_error = "" if error == OK else "Desk layout replace: " + error_string(error)
	_layout_dirty = error != OK


func _sync_staged_materials() -> void:
	if _material_cards == null: return
	var editor: Control = _page.hud.design_workbench()
	if editor.has_method("staged_raw_id") and _material_cards.has_method("set_staged_raw"):
		_material_cards.set_staged_raw(editor.staged_raw_id())


func _sync_reward_input() -> void:
	# Exclude actual interactive slips, not their mouse-ignoring tray.
	for prop_id in _props._props:
		var live: Array = _props._exclusions.get(prop_id, []).filter(is_instance_valid)
		_props._exclusions[prop_id] = live
		for slip in _fax._reward_slips.values(): _props.add_exclusion(prop_id, slip)


func sync_state(state: Dictionary) -> void:
	_sync_staged_materials()
	_sync_context_layers(state)
	for box: Control in _token_boxes.values(): box.sync_state(state)
	if _material_cards != null:
		_material_cards.sync_state(state)
		_sync_module_papers()
	_fax.sync_reward_state(state.get("event_materials",state.get("design_state",{}).get("event_materials",[])))
	_sync_reward_input()
	_monitor.sync_state(state)
	var archive_state := state.duplicate(true)
	archive_state.family_records = _page.simulation.families.duplicate(true)
	_archive.sync_state(archive_state)
	_event_archive.clear()
	for event in state.get("events", []):
		_event_archive[str(event.get("instance_id", ""))] = event.duplicate(true)
	var sources: Array = []
	var keys: Dictionary = {}
	for index in state.get("economy_log", []).size():
		var text := str(state.economy_log[index]).replace("；购买系统尚未设计。", "").replace("; 购买系统尚未设计。", "")
		sources.append({"id":"points/%d/%s" % [index, text.sha256_text()], "text":"点数流水\n" + text})
	for event in state.get("events", []):
		var text := "H%d / %s\n%s\n67：%s" % [int(event.get("hour", 0)), str(event.get("title", "事件")), str(event.get("impact_text", "")), str(event.get("mentor_comment", ""))]
		sources.append({"id":"event/" + str(event.get("instance_id", "")) + "/" + text.sha256_text(), "event_id":str(event.get("instance_id", "")), "text":text})
	for source in sources: keys[source.id] = true
	var replace := int(state.get("seed", _page.simulation.seed_value)) != _journal_seed or int(state.get("hour", 0)) < _journal_hour
	for key in _journal_known:
		if str(key).begins_with("status/"): continue
		if not keys.has(key): replace = true
	if replace:
		_journal.clear()
		_journal_known.clear()
		_status_text = ""
	_journal_seed = int(state.get("seed", _page.simulation.seed_value))
	_journal_hour = int(state.get("hour", 0))
	for source in sources:
		if _journal_known.has(source.id): continue
		_journal.append(source)
		_journal_known[source.id] = true
	var status := str(state.get("status", ""))
	if status != _status_text and not status.is_empty():
		_status_text = status
		var id := "status/%d" % _journal.size()
		_journal.append({"id":id, "text":"H%d / %s\nMeme %d · 注意力 %d\n曝光 %d · 采用 %d" % [_journal_hour, status, int(state.get("meme_points", 0)), int(state.get("attention_budget", 0)), int(state.get("exposed", 0)), int(state.get("adopted", 0))]})
		_journal_known[id] = true
	_printer.sync_entries(_journal)


func reset_journal() -> void:
	for item: Control in _context_layer_items.values(): item.queue_free()
	_context_layer_items.clear()
	if _material_cards != null: _material_cards.clear_cards()
	_event_archive.clear()
	_pending_archive_event = {}
	_archive.reset_browser()
	_journal.clear()
	_journal_known.clear()
	_journal_seed = -1
	_journal_hour = 0
	_status_text = ""
	_printer.sync_entries([])
	_monitor.reset_history()
	_fax.reset_station()


func _process(_delta: float) -> void:
	if _page == null: return
	_clock_presenter.tick()
	var fax_focused := bool(_fax.get("_focused"))
	var archive_focused := bool(_archive.get("_focused"))
	_art.stamp.visible = not fax_focused and not archive_focused
	_shadows.stamp.visible = presentation.shadows_enabled and _art.stamp.visible
	_shadows.folder.visible = presentation.shadows_enabled and not archive_focused
	var blocked: bool = _page.hud.modal_visible() or _page.tools.visible or _stack.is_switching() or (_page._shell != null and _page._shell.blocks_input())
	_sync_reader_blocks()
	var enabled := not blocked and not fax_focused and not archive_focused
	if _props.enabled != enabled: _props.set_enabled(enabled)
	if _material_cards != null: _material_cards.set_enabled(enabled)
	for item: Control in _context_layer_items.values(): item.set_interaction_enabled(enabled)
	var editor: Control = _page.hud.design_workbench()
	var design_enabled: bool = enabled and _page.startup_ready() and _active_sheet != "map" and _page.simulation.phase != "event"
	if editor.has_method("set_interaction_enabled"):
		editor.set_interaction_enabled(design_enabled)
	if editor.has_method("culture_physics"):
		var culture: Control = editor.culture_physics()
		if culture != null: culture.set_enabled(design_enabled and _active_sheet == "cultivate")
	_country_layer.visible = _active_sheet == "map" and enabled
	_page.atlas.drawer.hide()
	_page.atlas.hover_note.hide()
	_page.atlas.get_node("%SpeedControl").disabled = blocked or interaction_paused() or _active_sheet != "map" or _page.simulation.phase != "running"
	_speed_strip.sync(_page.simulation.speed, enabled and _active_sheet == "map" and _page.simulation.phase == "running")
	if _layout_dirty and not _stack.is_switching() and not _props.inspection().dragging and _props.inspection().pressed.is_empty(): _save_placement()
	# Dynamic menus and retained slips use the same explicit tooltip opt-in.
	PaperStyle.suppress_tooltips(self)
	PaperStyle.suppress_tooltips(_page.hud)
	PaperStyle.suppress_tooltips(_page.tools)


func inspection() -> Dictionary:
	var shades: Dictionary = {}
	for id in _shadows: shades[id] = _shadows[id].inspection()
	return {"layout_version":6,"active_sheet":_active_sheet,"stack_rect":_stack_rect,"map_rect":_stack.map_rect(),
		"context_layer_items":_context_layer_inspection(), "tabletop_materials":_material_cards.inspection() if _material_cards != null else {},
		"archive":_archive.inspection(), "speed_strip":_speed_strip.inspection(),"token_boxes":{"stance":_token_boxes.stance.inspection(),"pragmatic":_token_boxes.pragmatic.inspection()},"dependent_updates":_dependent_updates,"receipt_layer":_receipt_layer.layer,
		"paper_stack":_stack.inspection(), "fax_station":_fax.inspection(), "interaction":_props.inspection(),
		"clock":_clock_presenter.inspection(), "clock_rect":clock_rect(),"clock_texture":_art.clock.texture.resource_path,
		"fax_rect":_art.fax.get_global_rect(),"folder_rect":_art.folder.get_global_rect(),"printer_rect":_art.printer.get_global_rect(),
		"crt_rect":_art.crt.get_global_rect(),"crt_texture":_textures.crt.resource_path,"crt_below_printer":_monitor.z_index < _art.printer.z_index,
		"printer_outlet":_outlet,"receipt_width":_outlet_width,"receipt_rotation":_printer.rotation,"log_printer":_printer.inspection(),
		"meme_monitor":_monitor.inspection(),"wires":{"fax":_wires.fax.points,"printer":_wires.printer.points},
		"light_point_fixed":true,"light_position":_light.global_position,"light_height":_light.get_meta("height"),
		"silkscreen_shader":FixedInk.resource_path,"hover_shader":TornHover.resource_path,"shadows":shades,
		"paper_texture":_textures.map_print_paper.resource_path,"layout_error":_layout_error,"layout_path":LAYOUT_PATH}


func _place_context_layer(record: Dictionary, point: Vector2) -> void:
	var id := str(record.get("plane_id",""))
	if id.is_empty(): return
	if _context_layer_items.has(id):
		var existing: Control = _context_layer_items[id]
		existing.global_position = point - existing.size * 0.5
		return
	var slice: Control = _page.hud.design_workbench().context_slice()
	var item: Control = slice.create_slice_item(record)
	item.name = "Layer_" + str(record.layer)
	_page.hud.add_child(item)
	item.size = Vector2(220,220)
	item.global_position = point - item.size * 0.5
	item.z_index = 21
	for prop: Dictionary in _props.inspection().props:
		_props.add_exclusion(str(prop.id),item)
	_context_layer_items[id] = item
	item.item_dropped.connect(func(_layer: String,plane_id: String,drop_point: Vector2):
		if _active_sheet != "cultivate" or _page._interface_paused(): return
		if slice.accept_tabletop_layer(item.record,drop_point):
			_context_layer_items.erase(plane_id)
			item.queue_free())

func _sync_context_layers(state: Dictionary) -> void:
	var design: Dictionary = state.get("design_state",{})
	for layer: String in design.get("context_layers",{}):
		var row: Dictionary = design.context_layers[layer]
		var id := str(row.get("plane_id",""))
		if id.is_empty(): continue
		if bool(row.get("attached",true)):
			if _context_layer_items.has(id):
				var item: Control = _context_layer_items[id]
				_context_layer_items.erase(id)
				item.queue_free()
		elif not _context_layer_items.has(id):
			var index: int = ["language","group","topics","stance","pragmatic"].find(layer)
			_place_context_layer({"layer":layer,"plane_id":id,"snapshot":state.duplicate(true),"depth":0.1+index*0.2},Vector2(190+index*34,size.y-155))

func _context_layer_inspection() -> Dictionary:
	var result := {}
	for id: String in _context_layer_items: result[id] = _context_layer_items[id].inspection()
	return result
