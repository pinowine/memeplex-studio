extends Control

const DESK_SIZE := Vector2(1600, 900)
const RoomEnvironment := preload("res://scripts/presentation/studio/desk/desk_environment.gd")
const CameraRig := preload("res://scripts/presentation/studio/desk/desk_camera_rig.gd")

const ShadowObject := preload("res://scripts/presentation/studio/desk/desk_object_shadow.gd")
const LogPrinter := preload("res://scripts/presentation/studio/devices/printer/desk_log_printer.gd")
const MonitorPanel := preload("res://scripts/presentation/studio/devices/monitor/desk_monitor_panel.gd")
const Handwriting := preload("res://scripts/presentation/studio/desk/desk_handwriting.gd")
const SlotReader := preload("res://scripts/presentation/studio/paper/desk_slot_reader.gd")
const HoverStrip := preload("res://scripts/presentation/studio/desk/desk_hover_strip.gd")
const PropInteraction := preload("res://scripts/presentation/studio/desk/desk_prop_interaction.gd")
const RuledContacts := preload("res://scripts/presentation/studio/paper/desk_ruled_contacts.gd")
const SpeedStrip := preload("res://scripts/presentation/studio/devices/clock/desk_speed_strip.gd")
const MaterialCards := preload("res://scripts/presentation/studio/paper/desk_material_cards.gd")
const FaxStation := preload("res://scripts/presentation/studio/devices/fax/desk_fax_station.gd")
const PaperStyle := preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const FixedInk := preload("res://shaders/studio/desk_fixed_light.gdshader")
const TornHover := preload("res://shaders/ui/desk_torn_hover.gdshader")
const PRINTER_CROP := Rect2(90, 45, 1130, 930)
const PRINTER_SLOT := Rect2(334, 932, 646, 4)
const FAX_SLOT := Rect2(418, 134, 650, 4)
@export var presentation: DeskPresentation = preload("res://data/presentation/studio/desk_presentation.tres")

var _token_request_index := 0
var _environment: Control
var _component_target := ""
var _occluder_positions: Dictionary = {}
var _occluder_motion: Tween
var _blank_pressed := false
var _blank_press_point := Vector2.ZERO
var _camera: Camera2D
var _revealed_focus := ""
var _focus_reveal_count := 0
var _pending_sheet := ""
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
var _monitor: Control
var _hover_strip: Control
var _slot_reader: Control
var _slot_return_state: Dictionary = {}
var _slot_details: Dictionary = {}
var _pending_material_details: Dictionary = {}
var _slot_restoring := false
var _material_storage_visible := false
var _fax: DeskFaxStation
var _speed_strip: DeskSpeedStrip
var _token_boxes: Dictionary = {}
var _material_cards: DeskMaterialCards
var _context_layer_items: Dictionary = {}
var _receipt_layer: CanvasLayer
var _event_archive: Dictionary = {}
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


func slot_details_active() -> bool:
	return not _slot_return_state.is_empty()

func _slot_paper_rect() -> Rect2:
	var view := get_viewport_rect().size
	var width := minf(430.0,view.x*.32)
	return Rect2(view.x-width-28,48,width,maxf(210,minf(560,view.y-90)))

func _context_slot_pressed(layer: String, index: int, viewport_rect: Rect2) -> void:
	if slot_details_active() or _camera.inspection().state != "focused" or _revealed_focus != "sheet/cultivate": return
	if _page._interface_paused() or not _page.startup_ready(): return
	var board: Control = _page.hud.design_workbench().context_slice()
	var layer_data: Dictionary = board._layers().get(layer,{})
	var info: Dictionary = {}
	var slots: Array = layer_data.get("slots",[])
	if index >= 0 and index < slots.size():
		var resource_id: String = str(slots[index].get("resource_id",slots[index].get("id","")))
		info = board._resource(resource_id)
	var names := {"language":"语言","group":"人群","topics":"话题","stance":"政治立场","pragmatic":"语用"}
	var title: String = str(info.get("title",names.get(layer,layer)))
	var body: String = str(info.get("description",info.get("text","")))
	var instructions := {
		"language":"语言决定表达使用的语言。默认一个槽，释义补丁可增加第二个。至少保留一个来源有效且已挂接的语言，才能推进或发布。",
		"group":"人群决定表达面向的群体。默认一个槽，对照补丁可增加第二个。至少保留一个来源有效且已挂接的人群，才能推进或发布。",
		"topics":"话题用横向纸条安装；抓取纸舌移出。空位不会凭空产生材料。",
		"stance":"横轴：自由—威权；纵轴：平等—等级。空心点是起点，实心点是当前位置。一次沿一个轴移动，每步0.1；离开起点使用对应筹码，返回归还。",
		"pragmatic":"横轴：真诚—反讽；纵轴：支持—反对。一次沿一个轴移动，每步0.1。对应筹码数量可在显示器的语用模式查看。"}
	if not body.is_empty(): body += "\n\n"
	body += str(instructions.get(layer,""))
	if layer in ["language","group"]:
		body += DeskLocalization.source_format("\n\n当前容量：%d；本次查看第%d槽。", [_page.simulation.design_state.context_slot_capacity(layer),index+1])
	_slot_details = {"title":title,"body":body,"layer":layer,"slot":index}
	_slot_return_state = {"camera":_camera.capture_view(),"revealed_focus":_revealed_focus,"active_sheet":_active_sheet}
	_slot_restoring = false
	var world_rect: Rect2 = get_viewport().get_canvas_transform().affine_inverse()*viewport_rect
	_camera.focus_slot("slot/"+layer+"/"+str(index),world_rect,1.9)
	_sync_reader_blocks()

func close_slot_details() -> void:
	if not slot_details_active() or _slot_restoring: return
	_slot_restoring = true
	_slot_reader.hide_details()
	_camera.restore_view(_slot_return_state.camera)

func _slot_view_restored() -> void:
	if not _slot_restoring: return
	_revealed_focus = str(_slot_return_state.get("revealed_focus","sheet/cultivate"))
	_active_sheet = str(_slot_return_state.get("active_sheet",_active_sheet))
	_slot_return_state = {}
	_slot_details = {}
	_slot_restoring = false
	_set_sheet_content_visible(true)
	_sync_reader_blocks()

func _cancel_slot_details() -> void:
	_slot_return_state = {}
	_slot_details = {}
	_slot_restoring = false
	if _slot_reader != null: _slot_reader.hide_details()

func _slot_pointer_guard(event: InputEvent) -> bool:
	if not slot_details_active(): return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_slot_details()
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _slot_reader.handles_viewport_point(_foreground_point(event.position)):
			close_slot_details()
			return true
	return false

func _slot_detail_inspection() -> Dictionary:
	return {"active":slot_details_active(),"restoring":_slot_restoring,"details":_slot_details.duplicate(true),"return_state":_slot_return_state.duplicate(true),"paper":_slot_reader.inspection() if _slot_reader != null else {}}

func _update_material_storage(_enabled: bool) -> void:
	_material_storage_visible = false
	if _material_cards != null: _material_cards.visible = true


func _update_hover_strip() -> void:
	if _hover_strip == null: return
	var point := get_viewport().get_mouse_position()
	var info: Dictionary = _material_cards.hover_info(point) if _material_cards != null else {}
	if info.is_empty(): info = _monitor.hover_info(point)
	var fax_hint: String = _fax.hover_details(point)
	if info.is_empty() and not fax_hint.is_empty(): info = {"title":"传真情报","hint":fax_hint}
	var board: Control = _page.hud.design_workbench().context_slice()
	if info.is_empty() and board.is_visible_in_tree(): info = board.hover_info(point)
	if info.is_empty():
		var id: String = str(_props.inspection().get("hovered",""))
		var labels := {"fax":"传真机","printer":"日志打印机","crt":"点数显示器","folder":"档案与材料收纳","phonebook":"通讯录","clock":"时钟","speed":"播放速度","sheet/map":"世界","sheet/edit":"编辑","sheet/cultivate":"培养","sheet/spread":"传播"}
		if labels.has(id):
			info = {"title":labels[id],"hint":"移向旁边取用材料；单击查档案" if id == "folder" else "单击聚焦"}
	if info.has("text") and not info.has("description"): info.description = str(info.text)
	if info.is_empty(): _hover_strip.clear_hover()
	else: _hover_strip.show_hover(info)
	if not _component_target.is_empty() and _camera.inspection().state == "focused":
		_show_component_details(info)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_priority = 30
	for id in ["desk_surface", "folder", "paper_texture", "blank_print_paper"]:
		_textures[id] = load("res://assets/image/textures/studio/desk/" + id + ".png") as Texture2D
	for id in ["fax_downward", "crt_clean", "phonebook", "stamp_prop", "stamp_67", "landscape_paper", "portrait_67", "map_print_paper", "design_print_paper", "map_square_note", "design_square_note"]:
		_textures[id] = load("res://assets/image/textures/studio/desk/" + id + ".png") as Texture2D
	_textures.fax = _textures.fax_downward
	_textures.crt = load("res://assets/image/textures/studio/desk/monitor_body.png")
	_textures.desk_surface = load("res://assets/image/textures/studio/desk/wood_grain.png")
	_textures.stamp = _textures.stamp_prop
	_textures.folder = load("res://assets/image/textures/studio/desk/folder_closed.png")
	_textures.folder_open = load("res://assets/image/textures/studio/desk/folder_open.png")
	_textures.note = load("res://assets/image/textures/studio/desk/ruled_note.png")
	_textures.tape = load("res://assets/image/textures/studio/desk/clear_tape.png")
	var printer := AtlasTexture.new()
	printer.atlas = load("res://assets/image/textures/studio/desk/receipt_printer.png")
	printer.region = PRINTER_CROP
	_textures.printer = printer
	_art.desk_surface = _image("DeskSurface", _textures.desk_surface, self)
	var wood := ShaderMaterial.new()
	wood.shader = load("res://shaders/studio/desk_wood_surface.gdshader")
	_art.desk_surface.material = wood
	_environment = RoomEnvironment.new()
	_environment.name = "FiniteDeskEnvironment"
	add_child(_environment)
	_environment.configure(_art.desk_surface)


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
	# Keep the reference composition at every window size without editing local plugin settings.
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var terminal_theme: Theme = page.hud.theme
	Handwriting.apply_to(page.hud)
	Handwriting.apply_to(page.atlas)
	Handwriting.apply_to(page.spread)
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
		# The retired form owns state only; its pages are mounted on the real paper stack.
		if panel != page.hud.get_node("%Workbench"):
			_add_grain(panel)
		PaperStyle.apply_buttons(panel)
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
	_stack = load("res://scripts/presentation/studio/paper/desk_sheet_stack.gd").new()
	_stack.name = "PaperStack"
	add_child(_stack)
	_stack.configure(page.atlas.map_input, page.atlas.get_node("%MapFinish"), page.spread, workbench,
		{"paper":_textures.map_print_paper, "map_paper":_textures.map_print_paper, "design_paper":_textures.design_print_paper,
		"edit_paper":_textures.design_print_paper,"cultivate_paper":_textures.blank_print_paper,"spread_paper":_textures.landscape_paper,
		"map_note":_textures.map_square_note,"design_note":_textures.design_square_note})
	_stack.switch_started.connect(_sheet_started)
	_stack.switch_completed.connect(_sheet_settled)
	_clock_presenter = load("res://scripts/presentation/studio/devices/clock/desk_clock_presenter.gd").new()
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
	_monitor = MonitorPanel.new()
	_monitor.name = "MemeMonitor"
	_monitor.font_size = 11
	_monitor.screen_padding = 6
	_monitor.curve_height = 35
	_monitor.z_index = 1
	_monitor.theme = terminal_theme
	_art.crt.add_child(_monitor)
	_monitor.configure(page.simulation.design_state.rules)
	_monitor.token_released.connect(_drop_token)
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
	_props = PropInteraction.new()
	_props.name = "DeskInteractions"
	add_child(_props)
	_props.clicked.connect(_prop_clicked)
	_props.moved.connect(_prop_moved)
	_props.hovered.connect(_prop_hovered)
	# Reverse tree input order gives desk props first refusal before fax focus.
	_props.reparent(page.hud)
	for id in ["fax", "printer"]:
		var cable := TextureRect.new()
		cable.name = "TelephoneCable" if id == "fax" else "DataCable"
		cable.texture = load("res://assets/image/textures/studio/desk/equipment_cable.png")
		cable.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cable.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cable.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		cable.z_index = 0
		page.hud.add_child(cable)
		_wires[id] = cable
	_page.hud.configure_desk(Rect2(1, 1, 1, 1), self)
	# Subscribe only after every layout dependency exists; aspect changes can resize synchronously.
	resized.connect(_layout)
	_layout()
	_register_props()
	# Fixed desk coordinates intentionally do not import or overwrite saved free layouts.
	presentation.changed.connect(_update_prop_dependents)
	_update_contacts()
	_material_cards = MaterialCards.new()
	_material_cards.name = "TabletopMaterials"
	_material_cards.show()
	_material_cards.z_index = 20
	page.hud.add_child(_material_cards)
	page.hud.move_child(_material_cards, 0)
	_material_cards.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material_cards.configure(page.simulation.design_state.rules, _light, _screen_ink(_textures.blank_print_paper))
	_fax.viewport_exclusion = func(point: Vector2) -> bool:
		return _foreground_ui_handles(point) or _material_cards.handles_viewport_point(point)
	_material_cards.set_event_output_mode(true)
	_material_cards.set_storage_area(Rect2(1268,342,300,270))
	_material_cards.item_clicked.connect(_inspect_material)
	_material_cards.item_dropped.connect(_drop_material)
	_material_cards.release_module.connect(_unclip_module)
	page.hud.material_tabletop_requested.connect(_material_cards.request_item)
	var editor: Control = page.hud.design_workbench()
	if editor.has_signal("context_layer_detached"):
		editor.context_layer_detached.connect(_place_context_layer)
	if editor.has_signal("context_resource_detached"):
		editor.context_resource_detached.connect(func(record: Dictionary,point: Vector2) -> void:
			_material_cards.place_existing_item(str(record.get("kind","")),str(record.get("id","")),point))


	_fax.set_fixed_desktop_mode(true)
	_fax.set_external_details(true)
	_fax.details_changed.connect(_fax_details_changed)
	_fax.history_selected.connect(_history_selected)
	_fax.set_output_stack_area(Rect2(1300,345,244,300))
	_fax.set_continuous_output(true)
	_fax.camera_focus_requested.connect(_fax_camera_requested)
	_camera = CameraRig.new()
	_camera.name = "DeskCamera"
	_page.add_child(_camera)
	_camera.focus_arrived.connect(_camera_arrived)
	_camera.overview_arrived.connect(_camera_overview_arrived)
	_camera.view_restored.connect(_slot_view_restored)
	_camera.configure(DESK_SIZE)
	for layer: CanvasLayer in _physical_layers():
		layer.follow_viewport_enabled = true
		layer.follow_viewport_scale = 1.0
	var controls := CanvasLayer.new()
	controls.name = "DeskCameraControls"
	controls.layer = 45
	_page.add_child(controls)
	_slot_reader = SlotReader.new()
	_slot_reader.name = "SlotExplanationPaper"
	controls.add_child(_slot_reader)
	_slot_reader.configure(Handwriting.FONT, _textures.paper_texture)
	_slot_reader.option_selected.connect(func(index: int): _fax.choose_response(index))
	_slot_reader.contact_selected.connect(func(index: int): _fax.select_contact(index))
	_hover_strip = HoverStrip.new()
	_hover_strip.name = "DeskInformationSlip"
	_hover_strip.z_index = 21
	page.hud.add_child(_hover_strip)
	_hover_strip.configure(Handwriting.FONT, _textures.paper_texture)
	_place(_hover_strip, Rect2(835,58,410,74))
	var board: Control = editor.context_slice()
	board.slot_pressed.connect(_context_slot_pressed)
	_props.pointer_guard = _desktop_pointer_guard
	_props.viewport_exclusion = func(point: Vector2) -> bool:
		return _foreground_ui_handles(point) or _monitor.handles_viewport_point(point) or _material_cards.handles_viewport_point(point)
	for layer: String in _token_boxes:
		_token_boxes[layer].token_released.connect(_drop_token)
	_set_sheet_content_visible(true)
	PaperStyle.suppress_tooltips(self)
	PaperStyle.suppress_tooltips(page.hud)

func _physical_layers() -> Array[CanvasLayer]:
	var result: Array[CanvasLayer] = []
	for path: String in ["DeskLayer", "DemoLayer", "SpreadLayer"]:
		var layer := _page.get_node_or_null(path) as CanvasLayer
		if layer != null: result.append(layer)
	for layer: CanvasLayer in _stack._layers.values(): result.append(layer)
	var clock_layer := _clock.get_parent() as CanvasLayer
	if clock_layer != null: result.append(clock_layer)
	result.append(_country_layer)
	result.append(_receipt_layer)
	return result

func _set_sheet_content_visible(value: bool) -> void:
	for id: String in _stack._contents:
		_stack._contents[id].visible = value and id == _active_sheet
	var map_visible := value and _active_sheet == "map"
	_page.atlas.map_input.visible = map_visible
	_page.atlas.get_node("%MapFinish").visible = map_visible
	_page.spread.visible = map_visible

func focus_component(id: String) -> bool:
	if id == "phonebook" and _page.has_meta("studio3d"): return false
	if _camera == null or _page.hud.modal_visible(): return false
	if _page._shell != null and _page._shell.blocks_input(): return false
	if _stack.is_switching() or id == "folder": return false
	if slot_details_active(): _cancel_slot_details()
	if _fax.inspection().focused: _fax.close_focus()
	_restore_occluders()
	_component_target = "" if id.begins_with("sheet/") else id
	if _slot_reader != null: _slot_reader.hide_details()
	_revealed_focus = ""
	_set_sheet_content_visible(true)
	if id.begins_with("sheet/"):
		return _camera.focus_on(id, Rect2(Vector2.ZERO,DESK_SIZE), 1.35 if _page.has_meta("studio3d") else 1.0)
	if id not in ["fax","phonebook","crt","clock","printer","speed"]: return false
	var node: Control = _clock if id == "clock" else (_speed_strip if id == "speed" else _art[id])
	if id == "phonebook": _move_occluder("fax",Vector2(290,95))
	var center := node.get_global_transform() * (node.size * .5)
	return _camera.focus_equipment(id, center, node.size * node.scale, node.get_global_transform().get_rotation(), 1.5 if id == "fax" else 1.0)


func _camera_arrived(id: String) -> void:
	_sync_reader_blocks()
	if id.begins_with("slot/"):
		if slot_details_active() and not _slot_restoring:
			_slot_reader.show_details(_slot_details,get_viewport().get_visible_rect())
		return
	_revealed_focus = id
	_focus_reveal_count += 1
	if id.begins_with("sheet/"):
		var sheet := id.trim_prefix("sheet/")
		_pending_sheet = sheet
		_page.hud.show_sheet(sheet)
		if not _stack.is_switching():
			_active_sheet = sheet
			_set_sheet_content_visible(true)
	elif id in ["fax", "phonebook"]:
		_fax.reveal_after_camera("phone")
	elif id.begins_with("fax/"):
		_fax.reveal_after_camera(id.trim_prefix("fax/"))
	if not _component_target.is_empty(): _show_component_details()
	_open_pending_material_details()
	_fit_settings()


func _fax_camera_requested(mode: String) -> void:
	if _camera == null: return
	if not _occluder_positions.is_empty(): _restore_occluders()
	_component_target = "fax/"+mode
	_revealed_focus = ""
	_set_sheet_content_visible(true)
	var node: Control = _art.fax
	if mode in ["archive","paper"]:
		var printed: Control = _fax.history_focus_page()
		if printed != null: node = printed
	var center := node.get_global_transform()*(node.size*.5)
	_camera.focus_equipment("fax/"+mode,center,node.size,node.get_global_transform().get_rotation(),1.5 if mode == "phone" else 1.0)


func _camera_overview_arrived() -> void:
	_cancel_slot_details()
	_component_target = ""
	_revealed_focus = ""
	_pending_sheet = ""
	_set_sheet_content_visible(true)
	if _fax != null and _fax.inspection().focused: _fax.close_focus()
	_restore_occluders()


func return_overview() -> void:
	_pending_material_details = {}
	if slot_details_active():
		close_slot_details()
		return
	_component_target = ""
	_revealed_focus = ""
	_pending_sheet = ""
	if _slot_reader != null: _slot_reader.hide_details()
	if _fax != null and _fax.inspection().focused: _fax.close_focus()
	_restore_occluders()
	_set_sheet_content_visible(true)
	if _camera != null: _camera.return_overview()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _camera != null and _camera.inspection().state != "overview":
			return_overview()
			get_viewport().set_input_as_handled()

func _drop_token(token_id: String, point: Vector2) -> void:
	if _active_sheet != "cultivate" or _revealed_focus != "sheet/cultivate" or _page._interface_paused() or _page.hud.modal_visible() or _camera.inspection().state != "focused": return
	var board: Control = _page.hud.design_workbench().context_slice()
	var layer := "stance" if token_id in ["freedom","authority","equality","hierarchy"] else "pragmatic"
	var info: Dictionary = board.inspection().get("layers",{}).get(layer,{})
	if info.is_empty(): return
	var local := board.get_global_transform_with_canvas().affine_inverse() * point
	if not (info.get("axis_rect",Rect2()) as Rect2).has_point(local): return
	var values := {"freedom":[0,-1],"authority":[0,1],"equality":[1,-1],"hierarchy":[1,1],"sincere":[0,-1],"ironic":[0,1],"support":[1,-1],"opposition":[1,1]}
	if values.has(token_id):
		var action: Array = values[token_id]
		_token_request_index += 1
		board.perform("move_context_axis",{"layer":layer,"axis":"x" if int(action[0]) == 0 else "y","direction":action[1],"request_id":"tray:%s:%d" % [get_instance_id(),_token_request_index]})


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
	var view := DESK_SIZE
	_environment.layout_area()
	_light.position = Vector2(560,-180)
	_prop(_art.crt,Rect2(-8,-10,365,315),-0.30)
	_place(_clock,Rect2(355,-4,248,248))
	_clock.scale = Vector2.ONE
	_prop(_art.printer,Rect2(1335,-5,265,225),0.12)
	_prop(_art.fax,Rect2(1288,645,312,255),-0.23)
	_prop(_art.phonebook,Rect2(1188,745,165,120),0.42)
	_art.folder.hide()
	_shadows.folder.hide()
	_art.stamp.hide()
	_shadows.stamp.hide()
	_placed = true
	_stack_rect = Rect2(125,155,1140,740)
	_stack.layout_area(_stack_rect)
	_layout_speed_strip()
	_page.atlas.fit_map()
	_book_contacts.layout_book(Rect2(Vector2.ZERO,_art.phonebook.size))
	_place(_page.atlas.setup_note,Rect2(_stack_rect.position+Vector2(30,_stack_rect.size.y-100),Vector2((_stack_rect.size.x-60)*(.72 if _page.has_meta("studio3d") else 1.0),87)))
	_page.hud.configure_desk(_stack_rect,self)
	if _material_cards != null: _material_cards.set_storage_area(Rect2(1268,342,300,270))
	if _hover_strip != null: _place(_hover_strip,Rect2(835,58,410,74))
	_props.set_bounds(Rect2(-80,-100,1760,1100))
	_update_prop_dependents()
	_fit_settings()
	_fit_codex()


func _layout_token_inventory(_view: Vector2) -> void:
	# Both directional inventories are drawn inside the monitor.
	pass


func _prop(node: TextureRect, rect: Rect2, angle: float) -> void:
	_place(node, rect)
	node.pivot_offset = node.size * 0.5
	node.rotation = angle


func _layout_speed_strip() -> void:
	_place(_speed_strip,Rect2(592,32,215,80))
	_speed_strip.pivot_offset = _speed_strip.size*.5
	_speed_strip.rotation = 0.07


func _layout_receipt(view: Vector2) -> void:
	var machine: TextureRect = _art.printer
	var fitted := ShadowObject.fit_rect(machine.texture.get_size(), machine.size, machine.stretch_mode)
	var factor := fitted.size.x / PRINTER_CROP.size.x
	var local := fitted.position + (PRINTER_SLOT.position - PRINTER_CROP.position) * factor
	_outlet = machine.get_global_transform() * local
	_outlet_width = PRINTER_SLOT.size.x * factor
	if _page.has_meta("studio3d"):
		var mouth: Dictionary = _page.get_meta("studio3d").paper_exit("receipt_printer")
		_outlet = mouth.origin
		_outlet_width = mouth.width
	_printer.layout_area(Rect2(_outlet, Vector2(_outlet_width, view.y - _outlet.y + 24)))
	_printer.pivot_offset = Vector2.ZERO
	_printer.rotation = machine.rotation


func _layout_monitor() -> void:
	var machine: TextureRect = _art.crt
	var fitted := ShadowObject.fit_rect(machine.texture.get_size(),machine.size,machine.stretch_mode)
	var factor := fitted.size.x/machine.texture.get_width()
	_monitor.position = Vector2.ZERO
	_monitor.size = machine.size
	_monitor.rotation = 0.0
	var screen := Rect2(fitted.position+Vector2(180,215)*factor,Vector2(1060,590)*factor)
	var buttons := Rect2(fitted.position+Vector2(300,855)*factor,Vector2(830,175)*factor)
	_monitor.layout_console(screen,buttons)


func _update_prop_dependents() -> void:
	_dependent_updates += 1
	_layout_speed_strip()
	var view := DESK_SIZE
	_layout_receipt(view)
	_layout_monitor()
	_fax.layout_station(_art.fax.get_global_rect(), Rect2(Vector2.ZERO, view), FAX_SLOT)
	# Raster cables share the machine transform; their far ends leave the finite desk.
	_layout_cable("fax", _art.fax, Vector2(270,180), Vector2(140,215), 2.35)
	_layout_cable("printer", _art.printer, Vector2(234,68), Vector2(110,166), 0.1)
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
	for id in ["phonebook", "crt", "clock", "speed", "printer", "fax"]:
		if id == "phonebook" and _page.has_meta("studio3d"): continue
		var node: Control = _clock if id == "clock" else (_speed_strip if id == "speed" else _art[id])
		var hit := Rect2(Vector2.ZERO, node.size)
		if id == "fax": hit = Rect2(7,17,298,235)
		if id == "printer": hit = Rect2(7,9,250,207)
		if id == "crt": hit = Rect2(10,10,325,280)
		_props.register_prop(id, node, hit, id in ["folder", "crt", "clock", "printer", "fax"], false)
		var cores := {"clock":Rect2(38,41,140,146),"folder":Rect2(23,24,208,137),"crt":Rect2(30,30,174,130),
			"printer":Rect2(25,30,240,185),"fax":Rect2(25,36,265,168)}
		if cores.has(id): _props.set_collision_rect(id, cores[id])
		if id != "speed": _create_hover(id, _art[id])
	for layer in _token_boxes:
		var box: Control = _token_boxes[layer]
		# Fixed token trays own their input; the desk must not swallow token pickup.
		_create_hover("tokens/"+str(layer),box.background_node())
	for id in ["map", "edit", "cultivate", "spread"]:
		var sheet: Control = _stack.sheet_node(id)
		var tab: Control = _stack.tab_node(id)
		_props.register_prop("sheet/" + id, tab, Rect2(Vector2.ZERO, tab.size), false, false)
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
	var key := String(id)
	if key.begins_with("sheet/"):
		select_sheet(key.trim_prefix("sheet/"))
	elif key in ["fax","phonebook","crt","clock","printer","speed"]:
		focus_component(key)


func _prop_moved(id: StringName, _point: Vector2) -> void:
	_layout_dirty = not _restoring_placement
	if String(id).begins_with("tokens/") and not _restoring_placement:
		var layer := String(id).trim_prefix("tokens/")
		if _token_boxes.has(layer): _token_boxes[layer].set_meta("inventory_docked",false)
	# Moving one prop must not relayout stationary machines and their paper.
	if String(id) == "crt": _layout_monitor()
	if _shadows.has(String(id)): refresh_shadows([String(id)])
	if _hover.has(String(id)): _update_hover_item(_hover[String(id)])
	if String(id) == "stamp" and not _restoring_placement:
		_fax.stamp_at(_art.stamp.get_global_transform() * (_art.stamp.size * 0.5))


func _inspect_material(kind: String, id: String) -> void:
	if not _page.startup_ready(): return
	_pending_material_details = {"kind":kind,"id":id}
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
	if errors.is_empty(): _drop_material(str(record.get("kind","")),str(record.get("id","")),point)

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
	if _active_sheet == "map" or not _page.startup_ready() or _revealed_focus != "sheet/"+_active_sheet or _camera.inspection().state != "focused": return
	var editor: Control = _page.hud.design_workbench()
	if editor.accept_tabletop_item(kind, id, point):
		if kind == "module": _sync_module_papers()
		else: _material_cards.return_to_inventory(kind, id)


func _fax_focus_changed(focused: bool) -> void:
	_sync_reader_blocks()
	_page.atlas.set_speed(0 if focused or _page.hud.get_node("%Workbench").visible else _page.simulation.speed)
	if not focused:
		_component_target = ""
		if _slot_reader != null: _slot_reader.hide_details()
		_page._sync_setup()
		if _camera != null: _camera.return_overview()


func _open_event_archive(instance_id: String) -> void:
	if not _event_archive.has(instance_id) or _page.hud.modal_visible(): return
	if not _fax.select_history(instance_id): _fax.view_archived_event(_event_archive[instance_id])


func _update_contacts() -> void:
	var contacts: Array[Dictionary] = _fax.contacts_snapshot()
	_book_contacts.set_contacts(contacts)


func _fit_settings() -> void:
	if _page == null: return
	if _page.has_meta("studio3d"):
		_page.hud.layout_screen_modals()
		return
	var center := _camera.position if _camera != null else DESK_SIZE * 0.5
	_place(_page.hud.get_node("%SettingsMenu"), Rect2(center-Vector2(215,295),Vector2(430,590)))


func _fit_codex() -> void:
	if _page != null and _page.has_meta("studio3d"):
		_page.hud.layout_screen_modals()
		return
	if _page != null and _stack_rect.has_area(): _place(_page.hud.get_node("%CodexPanel"), _stack_rect)


func clock_rect() -> Rect2:
	return _clock.get_global_rect() if _clock != null else Rect2()


func interaction_paused() -> bool:
	if slot_details_active(): return true
	return _stack != null and (_stack.is_switching() or (_fax != null and _fax.interaction_focused()))


func _sync_reader_blocks() -> void:
	var blocked: bool = slot_details_active() or (_camera != null and _camera.inspection().state in ["travelling","returning"]) or _page.hud.modal_visible() or _stack.is_switching() or (_page._shell != null and _page._shell.blocks_input())
	_fax.set_interaction_blocked(blocked)


func select_sheet(id: String) -> void:
	if _page != null and _page.has_method("startup_ready") and not _page.startup_ready():
		_page.open_startup_call()
		return
	if _page != null and _page._shell != null and _page._shell.blocks_input(): return
	if _page == null or _page.hud.modal_visible() or _fax.inspection().focused: return
	if _stack.is_switching(): return
	focus_component("sheet/"+id)
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
	_set_sheet_content_visible(true)
	_page.atlas.fit_map()
	_page._sync_setup()
	_page.atlas.set_speed(0 if _active_sheet != "map" or _page._interface_paused() else _page.simulation.speed)
	_open_pending_material_details()


func receive_event(event: Dictionary) -> void:
	_fax.receive_event(event)
	_update_contacts()


func event_ready() -> bool:
	return _fax != null and _fax.inspection().event_state == "ready"


func _sync_reward_input() -> void:
	# Exclude actual interactive slips, not their mouse-ignoring tray.
	for prop_id in _props._props:
		var live: Array = _props._exclusions.get(prop_id, []).filter(is_instance_valid)
		_props._exclusions[prop_id] = live
		for slip in _fax.material_slips(): _props.add_exclusion(prop_id, slip)


func sync_state(state: Dictionary) -> void:
	_sync_context_layers(state)
	for box: Control in _token_boxes.values(): box.sync_state(state)
	if _material_cards != null:
		_material_cards.sync_state(state)
		_sync_module_papers()
	_fax.restore_output_history(state.get("events",[]))
	_fax.sync_reward_state(state.get("event_materials",state.get("design_state",{}).get("event_materials",[])))
	_sync_reward_input()
	_monitor.sync_state(state)
	if _hover_strip != null:
		var monitor_info: Dictionary = _monitor.inspection()
		var current: Dictionary = state.get("design_state",{}).get("context_draft",{})
		var current_text := str(current.get("text",""))
		if current_text.is_empty(): current_text = str(current.get("target",""))
		if current_text.is_empty() and str(monitor_info.title_source) != "none": current_text = str(monitor_info.title)
		_hover_strip.set_default_text(current_text)
	_event_archive.clear()
	for event in state.get("events", []):
		_event_archive[str(event.get("instance_id", ""))] = event.duplicate(true)
	var sources: Array = []
	var keys: Dictionary = {}
	for index in state.get("economy_log", []).size():
		var text := str(state.economy_log[index]).replace("；购买系统尚未设计。", "").replace("; 购买系统尚未设计。", "")
		var entry := {"id":"points/%d/%s" % [index,text.sha256_text()],"text":"点数流水\n"+text}
		if index < _page.simulation.economy.transactions.size():
			var transaction: Dictionary = _page.simulation.economy.transactions[index]
			entry.display_template = "点数流水\nH%d  %s%d Meme  %s → %d"
			entry.display_arguments = [transaction.hour,"+" if int(transaction.delta)>=0 else "",transaction.delta,transaction.reason,transaction.balance]
			entry.localize_arguments = [3]
		sources.append(entry)
	for event in state.get("events", []):
		var text := "H%d / %s\n%s\n67：%s" % [int(event.get("hour", 0)), str(event.get("title", "事件")), str(event.get("impact_text", "")), str(event.get("mentor_comment", ""))]
		sources.append({"id":"event/"+str(event.get("instance_id",""))+"/"+text.sha256_text(),"event_id":str(event.get("instance_id","")),"text":text,"display_template":"H%d / %s\n%s\n67：%s","display_arguments":[int(event.get("hour",0)),str(event.get("title","事件")),str(event.get("impact_text","")),str(event.get("mentor_comment",""))],"localize_arguments":[1,2,3]})
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
		var arguments: Array = [_journal_hour,status,int(state.get("meme_points",0)),int(state.get("attention_budget",0)),int(state.get("exposed",0)),int(state.get("adopted",0))]
		var template := "H%d / %s\nMeme %d · 注意力 %d\n曝光 %d · 采用 %d"
		_journal.append({"id":id,"text":template%arguments,"display_template":template,"display_arguments":arguments,"localize_arguments":[1]})
		_journal_known[id] = true
	_printer.sync_entries(_journal)


func reset_journal() -> void:
	for item: Control in _context_layer_items.values(): item.queue_free()
	_context_layer_items.clear()
	if _material_cards != null: _material_cards.clear_cards()
	_event_archive.clear()
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
	for id: String in ["map","edit","cultivate","spread"]:
		var key := "sheet/"+id
		if _props._props.has(key):
			var tab: Control = _stack.tab_node(id)
			_props._props[key].hit_rect = Rect2(Vector2.ZERO,tab.size)
	var fax_focused := _fax.interaction_focused()
	var archive_focused := false
	_art.stamp.visible = false
	_shadows.stamp.visible = presentation.shadows_enabled and _art.stamp.visible
	_shadows.folder.visible = false
	_art.folder.visible = false
	var blocked: bool = (_camera != null and _camera.inspection().state in ["travelling","returning"]) or _page.hud.modal_visible() or _stack.is_switching() or (_page._shell != null and _page._shell.blocks_input())
	_sync_reader_blocks()
	var enabled := not blocked and not fax_focused and not slot_details_active()
	_monitor.set_interaction_enabled(enabled)
	_monitor.set_token_interaction_enabled(enabled and _revealed_focus == "sheet/cultivate" and _camera.inspection().state == "focused")
	_update_material_storage(enabled)
	_update_hover_strip()
	for box: Control in _token_boxes.values(): box.set_interaction_enabled(enabled and _revealed_focus == "sheet/cultivate" and _camera.inspection().state == "focused")
	if _props.enabled != enabled: _props.set_enabled(enabled)
	if _material_cards != null: _material_cards.set_enabled(enabled)
	for item: Control in _context_layer_items.values(): item.set_interaction_enabled(enabled)
	var editor: Control = _page.hud.design_workbench()
	var design_enabled: bool = enabled and _page.startup_ready() and _active_sheet != "map" and _page.simulation.phase != "event" and _revealed_focus == "sheet/"+_active_sheet and _camera.inspection().state == "focused"
	if editor.has_method("set_interaction_enabled"):
		editor.set_interaction_enabled(design_enabled)
	_country_layer.visible = _active_sheet == "map" and enabled
	_page.atlas.drawer.hide()
	_page.atlas.hover_note.hide()
	_page.atlas.get_node("%SpeedControl").disabled = blocked or interaction_paused() or _active_sheet != "map" or _page.simulation.phase != "running"
	_speed_strip.sync(_page.simulation.speed, enabled and _active_sheet == "map" and _page.simulation.phase == "running")


func inspection() -> Dictionary:
	var shades: Dictionary = {}
	for id in _shadows: shades[id] = _shadows[id].inspection()
	return {"component_details":_component_detail_inspection(),"environment":_environment.inspection(),"fixed_layout":true,"world_size":DESK_SIZE,"desktop_camera":_camera.inspection() if _camera != null else {},"revealed_focus":_revealed_focus,"focus_reveal_count":_focus_reveal_count,"free_placement_enabled":false,"layout_persistence_enabled":false,"layout_version":8,"reference_layout":true,"handwritten_font":Handwriting.FONT.resource_path,"slot_details":_slot_detail_inspection(),"hover_strip":_hover_strip.inspection() if _hover_strip != null else {},"wood_texels_per_world":1254.0/384.0,"active_sheet":_active_sheet,"stack_rect":_stack_rect,"map_rect":_stack.map_rect(),
		"context_layer_items":_context_layer_inspection(), "tabletop_materials":_material_cards.inspection() if _material_cards != null else {},
		"archive":{}, "speed_strip":_speed_strip.inspection(),"token_boxes":{},"token_drawers_merged":true,"material_storage_visible":_material_storage_visible,"dependent_updates":_dependent_updates,"receipt_layer":_receipt_layer.layer,
		"paper_stack":_stack.inspection(), "fax_station":_fax.inspection(), "interaction":_props.inspection(),
		"clock":_clock_presenter.inspection(), "clock_rect":clock_rect(),"clock_texture":_art.clock.texture.resource_path,
		"fax_rect":_art.fax.get_global_rect(),"folder_rect":_art.folder.get_global_rect(),"printer_rect":_art.printer.get_global_rect(),
		"crt_rect":_art.crt.get_global_rect(),"crt_texture":_textures.crt.resource_path,"crt_below_printer":_monitor.z_index < _art.printer.z_index,
		"printer_outlet":_outlet,"receipt_width":_outlet_width,"receipt_rotation":_printer.rotation,"log_printer":_printer.inspection(),
		"meme_monitor":_monitor.inspection(),"wires":{"fax":_wires.fax.texture.resource_path,"printer":_wires.printer.texture.resource_path},
		"light_point_fixed":true,"light_position":_light.global_position,"light_height":_light.get_meta("height"),
		"silkscreen_shader":FixedInk.resource_path,"hover_shader":TornHover.resource_path,"shadows":shades,
		"paper_texture":_textures.map_print_paper.resource_path,"layout_error":_layout_error}


func _layer_storage_position(layer: String) -> Vector2:
	var index := ["language","group","topics","stance","pragmatic"].find(layer)
	return Vector2(150 + maxi(0,index) * 215, 930)

func _place_context_layer(record: Dictionary, point: Vector2) -> void:
	var id := str(record.get("plane_id",""))
	if id.is_empty(): return
	if _context_layer_items.has(id):
		var existing: Control = _context_layer_items[id]
		existing.position = _layer_storage_position(str(record.get("layer","")))
		return
	var slice: Control = _page.hud.design_workbench().context_slice()
	var item: Control = slice.create_slice_item(record)
	item.name = "Layer_" + str(record.layer)
	_page.hud.add_child(item)
	item.size = Vector2(200,54)
	item.position = _layer_storage_position(str(record.get("layer","")))
	item.z_index = 21
	for prop: Dictionary in _props.inspection().props:
		_props.add_exclusion(str(prop.id),item)
	_context_layer_items[id] = item
	item.item_dropped.connect(func(_layer: String,plane_id: String,drop_point: Vector2):
		if _active_sheet == "cultivate" and not _page._interface_paused() and slice.accept_tabletop_layer(item.record,drop_point):
			_context_layer_items.erase(plane_id)
			item.queue_free()
		else:
			item.position = _layer_storage_position(str(item.record.get("layer",""))))

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

func _layout_cable(id: String, machine: Control, port: Vector2, dimensions: Vector2, angle: float) -> void:
	var cable: TextureRect = _wires[id]
	cable.size = dimensions
	cable.pivot_offset = Vector2.ZERO
	cable.rotation = machine.rotation + angle
	# The generated connector is at source UV (.13,.92); its tip meets the socket.
	cable.position = machine.get_global_transform() * port - (Vector2(.13,.92) * dimensions).rotated(cable.rotation)

func _move_occluder(id: String, offset: Vector2) -> void:
	if _page.has_meta("studio3d"): return
	if _occluder_positions.has(id): return
	var node: Control = _art[id]
	_occluder_positions[id] = node.position
	_occluder_motion = create_tween()
	_occluder_motion.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_occluder_motion.tween_property(node,"position",node.position+offset,.32)
	_occluder_motion.parallel().tween_method(func(_value: float): _update_prop_dependents(),0.0,1.0,.32)

func _restore_occluders() -> void:
	if _occluder_motion != null and _occluder_motion.is_valid(): _occluder_motion.kill()
	if _occluder_positions.is_empty(): return
	# Restore the stored pose exactly; camera return supplies the visible transition.
	for id: String in _occluder_positions: _art[id].position = _occluder_positions[id]
	_occluder_positions.clear()
	_update_prop_dependents()

func _component_detail_inspection() -> Dictionary:
	return {"active":not _component_target.is_empty(),"target":_component_target,"paper":_slot_reader.inspection() if _slot_reader != null else {},"occluders":_occluder_positions.duplicate()}

func _component_details() -> Dictionary:
	if _component_target in ["fax","phonebook"] or _component_target.begins_with("fax/"):
		var mode := "archive" if _component_target == "fax/archive" else ("phonebook" if _component_target == "phonebook" else "phone")
		var details: Dictionary = _fax.component_details(mode)
		var paragraphs := PackedStringArray()
		for key: String in ["description","npc_text","status","number","log","impact","effect","mentor","gesture"]:
			var text := str(details.get(key,""))
			if not text.is_empty(): paragraphs.append(text)
		details.body = "\n\n".join(paragraphs)
		if mode == "archive": details.erase("contacts")
		if mode != "phonebook": details.erase("contacts")
		return details
	var descriptions := {
		"crt":{"title":"点数显示器","body":"下方三个键切换 Meme、政治立场和语用点数。Meme页保留变化曲线；其余两页显示四个方向已有的筹码。抓取方向格中的筹码，可拖到培养纸的对应坐标轴。"},
		"printer":{"title":"日志打印机","body":"点数流水和事件摘要会继续打印。单击纸上的事件记录，可查看对应的原始事件。"},
		"clock":{"title":"时间罗盘","body":"罗盘显示当前日期、季节与天气。时间推进遵守当前播放速度；查看说明不会改变模因与材料。"},
		"speed":{"title":"播放速度","body":"三个实体键控制暂停、正常播放和加速。只有世界页运行时可以推进时间。"}}
	return descriptions.get(_component_target,{"title":"工作台","body":"单击空白处或按 Esc，回到桌面。"}).duplicate(true)

func _show_component_details(hover: Dictionary = {}) -> void:
	if _slot_reader == null or _component_target.is_empty() or slot_details_active(): return
	var details := _component_details()
	if not hover.is_empty() and _component_target not in ["fax","phonebook"] and not _component_target.begins_with("fax/"):
		var text := DeskLocalization.text(str(hover.get("description",hover.get("text",hover.get("hint","")))))
		if hover.has("count") or hover.has("source_label"):
			details = _material_full_details(hover)
		else:
			if not text.is_empty(): details.body = text
			if not DeskLocalization.text(str(hover.get("title",""))).is_empty(): details.title = str(hover.title)
	# Avoid restarting the slide or resetting scroll when nothing changed.
	var reader_state: Dictionary = _slot_reader.inspection()
	if reader_state.details != details or not _slot_reader.is_visible_in_tree() or reader_state.phase in ["hidden","exiting"]:
		_slot_reader.show_details(details,get_viewport().get_visible_rect())

func _fax_details_changed(_record: Dictionary) -> void:
	if not _component_target.is_empty() and _camera != null and _camera.inspection().state == "focused": _show_component_details()

func _history_selected(_record: Dictionary) -> void:
	_component_target = "fax/archive"
	if _camera != null and _camera.inspection().state == "focused": _show_component_details()

func _foreground_point(point: Vector2) -> Vector2:
	if _page.has_meta("studio3d"):
		return _page.get_meta("studio3d").root_pointer_from_logical(point)
	return point

func _foreground_ui_handles(point: Vector2) -> bool:
	point = _foreground_point(point)
	if _slot_reader != null and _slot_reader.handles_viewport_point(point): return true
	return _page._shell != null and _page._shell.tutorial.handles_viewport_point(point)


func _desktop_pointer_guard(event: InputEvent) -> bool:
	# Foreground controls must reach GUI routing before blank-desk gestures.
	if event is InputEventMouse and _foreground_ui_handles(event.position):
		_blank_pressed = false
		return false
	if _slot_pointer_guard(event): return true
	if _camera == null or _page.hud.modal_visible(): return false
	if _page._shell != null and _page._shell.blocks_input(): return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_blank_pressed = _camera.inspection().state == "focused" and _blank_viewport_point(event.position)
			_blank_press_point = event.position
			return _blank_pressed
		if _blank_pressed:
			_blank_pressed = false
			if event.position.distance_to(_blank_press_point)<8 and _blank_viewport_point(event.position): return_overview()
			return true
	return false

func _blank_viewport_point(point: Vector2) -> bool:
	if _foreground_ui_handles(point): return false
	if _slot_reader != null and _slot_reader.handles_viewport_point(_foreground_point(point)): return false
	if _monitor.handles_viewport_point(point) or _material_cards.handles_viewport_point(point): return false
	if not _printer.event_at(_printer.get_global_transform_with_canvas().affine_inverse()*point).is_empty(): return false
	if _props._button_at(_fax,point) or _props._button_at(_speed_strip,point): return false
	if not _fax.hover_details(point).is_empty(): return false
	if _props._hit_prop(point) != &"": return false
	# Active paper is a work surface, not an exit target. Other desk space is blank.
	var sheet: Control = _stack.sheet_node(_active_sheet)
	var local := sheet.get_global_transform_with_canvas().affine_inverse()*point
	if _component_target.is_empty() and Rect2(Vector2.ZERO,sheet.size).has_point(local): return false
	return true

func _material_full_details(info: Dictionary) -> Dictionary:
	var parts := PackedStringArray()
	for key: String in ["description","gesture","unlock_hint"]:
		var text := str(info.get(key,""))
		if not text.is_empty(): parts.append(text)
	if info.has("count"): parts.append(DeskLocalization.source_format("可用数量：%s",str(info.count)))
	var source := str(info.get("source_label",""))
	if not source.is_empty(): parts.append(DeskLocalization.source_format("来源：%s",source))
	return {"title":str(info.get("title","")),"body":"\n\n".join(parts),"source_records":info.get("source_records",[]).duplicate(true)}

func _open_pending_material_details() -> void:
	if _pending_material_details.is_empty() or _stack.is_switching() or _camera.inspection().state != "focused": return
	var record := _material_cards.details_for_item(str(_pending_material_details.kind),str(_pending_material_details.id))
	_pending_material_details = {}
	if record.is_empty(): return
	_slot_details = _material_full_details(record)
	_slot_return_state = {"camera":_camera.capture_view(),"revealed_focus":_revealed_focus,"active_sheet":_active_sheet}
	_slot_restoring = false
	_slot_reader.show_details(_slot_details,get_viewport().get_visible_rect())
	_sync_reader_blocks()
