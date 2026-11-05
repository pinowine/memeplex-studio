## The simulation owns inventory; these cards only present and place it.
class_name DeskMaterialCards
extends Control

signal item_clicked(kind: String, id: String)
signal item_dropped(kind: String, id: String, point: Vector2)
signal release_module(slot: int, id: String)
signal stack_clicked(kind: String)

const CardFace := preload("res://scripts/presentation/studio/paper/desk_material_card_face.gd")
const Interaction = preload("res://scripts/presentation/studio/desk/desk_prop_interaction.gd")
const Paper = preload("res://assets/image/textures/studio/desk/blank_print_paper.png")
const Shade = preload("res://scripts/presentation/studio/desk/desk_object_shadow.gd")
const Hover = preload("res://shaders/ui/desk_torn_hover.gdshader")
const INVENTORIES := {"module":"module_inventory","language":"context_resource_inventory","group":"context_resource_inventory","topic":"context_resource_inventory","stance_token":"context_resource_inventory","pragmatic_token":"context_resource_inventory"}
const ResourceGraphic := preload("res://scripts/presentation/studio/context/desk_context_resource_graphic.gd")
const NeuronGraphic := preload("res://scripts/presentation/studio/design/desk_neuron_graphic.gd")
const STACK_KINDS := ["group", "language", "module", "topic"]
const STACK_TITLES := {"group":"群体", "language":"语言", "module":"补丁", "topic":"话题"}
const STACK_LAYOUT := {
	"group":{"offset":Vector2(16, 27), "angle":-3.0},
	"language":{"offset":Vector2(3, -3), "angle":2.0},
	"module":{"offset":Vector2(-2, 6), "angle":-2.0},
	"topic":{"offset":Vector2(0, 1), "angle":3.0}}
const RewardSlip := preload("res://scripts/presentation/studio/paper/desk_event_material_slip.gd")

class CardInteraction extends DeskPropInteraction:
	signal dropped_at(id: StringName, point: Vector2, origin: Vector2)
	var loose_only := false
	func _live_prop(id: StringName) -> bool:
		if not super._live_prop(id): return false
		if String(id).begins_with("stack/"): return true
		return not loose_only or int(get_parent()._cards[String(id)].get("clipped_slot", -1)) < 0

	func input_event(event: InputEvent) -> bool:
		var before := inspection()
		var release: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and before.dragging
		var id := StringName(before.pressed)
		var origin: Vector2 = _press_position
		var handled := super.input_event(event)
		if release and handled and inspection().input_diagnostic.last_transition == "drag_released":
			dropped_at.emit(id,event.position,origin)
		return handled

class StackSurface extends Control:
	var kind := "group"
	var title := ""
	var quantity := 0
	var highlighted := false
	var hovered := false
	var selected := false
	var _face: DeskMaterialCardFace

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_face = CardFace.new()
		_face.size = CardFace.minimum_card_size(kind)
		add_child(_face)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var palette: Dictionary = CardFace.PALETTES[kind]
		var dimensions := CardFace.minimum_card_size(kind)
		for index in range(mini(quantity, 2), 0, -1):
			var outline := CardFace.outline_for(kind, Rect2(Vector2(4, 3) + Vector2(2, 3) * index, dimensions - Vector2(10, 10)))
			draw_colored_polygon(outline, palette.body.darkened(.10 * index))
			outline.append(outline[0])
			draw_polyline(outline, palette.edge, 1.1, true)
		var caption := "松开收纳" if highlighted and hovered else ("空卡摞" if quantity == 0 else "库存卡片")
		_face.configure({"kind":kind, "title":title, "count":quantity, "source_label":DeskLocalization.text(caption)}, get_theme_default_font())
		_face.set_hovered(hovered)
		_face.set_selected(selected or highlighted)

class StackCard extends Control:
	signal chosen
	signal dragged(point: Vector2)
	signal dropped(point: Vector2)
	signal drag_cancelled
	var face: Control
	var overlay: Control
	var record: Dictionary
	var font: Font
	var token := false
	var _pressed := false
	var _dragging := false
	var _origin := Vector2.ZERO
	var _ghost: Control

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func():
			if not token: face.set_hovered(true))
		mouse_exited.connect(func():
			if not token: face.set_hovered(false))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_pressed = true
			_origin = get_viewport().get_mouse_position()
			accept_event()

	func _input(event: InputEvent) -> void:
		if not _pressed: return
		if event is InputEventMouseMotion:
			if event.button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
				cancel_drag()
				return
			if not _dragging and event.position.distance_to(_origin) >= 6:
				_dragging = true
				_ghost = ResourceGraphic.new() if token else CardFace.new()
				overlay.add_child(_ghost)
				_ghost.z_index = 100
				if token: _ghost.configure(record)
				else: _ghost.configure(record, font)
				_ghost.size = size
				face.modulate.a = .35
			if _dragging:
				_ghost.global_position = event.position - size * .5
				dragged.emit(event.position)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			get_viewport().set_input_as_handled()
			_pressed = false
			face.modulate.a = 1.0
			if _dragging:
				_ghost.queue_free()
				_ghost = null
				_dragging = false
				dropped.emit(event.position)
			elif Rect2(Vector2.ZERO, size).has_point(get_global_transform_with_canvas().affine_inverse() * event.position):
				chosen.emit()

	func cancel_drag() -> void:
		var was_active := _pressed or _dragging
		_pressed = false
		_dragging = false
		face.modulate.a = 1.0
		if is_instance_valid(_ghost): _ghost.queue_free()
		_ghost = null
		if was_active: drag_cancelled.emit()

	func _exit_tree() -> void:
		cancel_drag()

var _rules: MemeDesignRules
var _props: CardInteraction
var _cards: Dictionary = {}
var _design: Dictionary = {}
var _seen: Dictionary = {}
var _seed := -1
var _light: Node2D
var _ink: ShaderMaterial
var _enabled := true
var _last_light := Vector2.ZERO
var _spawn_area := Rect2(844,354,208,260)
var _pending_cards: Dictionary = {}
var _event_positions: Dictionary = {}
var _storage_sections: Dictionary = {}
var _storage_slots: Dictionary = {}
var _event_output_mode := false
var _stack_surfaces: Dictionary = {}
var _focus_kind := ""
var _focus_host: Control
var _focus_scroll: ScrollContainer
var _focus_grid: GridContainer
var _focus_rect := Rect2()
var _focus_signature := ""
var _focus_point_mapper: Callable
var _drop_kind := ""
var _drop_stack := ""
var _selected_key := ""

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_props = CardInteraction.new()
	_props.name = "MaterialInteractions"
	add_child(_props)
	_props.clicked.connect(_clicked)
	_props.moved.connect(_card_moved)
	_props.hovered.connect(_hovered)
	_props.dropped_at.connect(_released)
	resized.connect(_storage_resized)
	get_window().focus_exited.connect(_return_free_cards)

func configure(rules: MemeDesignRules, light: Node2D, ink: ShaderMaterial) -> void:
	_rules = rules
	_light = light
	_last_light = light.global_position
	_ink = ink
	if _ink != null: _ink.set_shader_parameter("light_position",_light.global_position)
	_build_storage_slots()
	_layout_inventory()

func set_enabled(value: bool, loose_only := false) -> void:
	if value == _enabled and loose_only == _props.loose_only: return
	_enabled = value
	_props.loose_only = loose_only
	_props.set_enabled(value)
	if not value: _return_free_cards()
	# Camera travel blocks dragging without removing physical paper from the desk.
	queue_redraw()

func set_event_output_mode(value: bool) -> void:
	if value == _event_output_mode: return
	_event_output_mode = value
	for card: Dictionary in _cards.values(): card.event_placed = false
	_layout_inventory()
	queue_redraw()

func release_event_cards(_record: Dictionary, _page: Control) -> void:
	# Event rewards remain on their printed sheet until the authority accepts a drag.
	_layout_inventory()

func set_spawn_area(area: Rect2) -> void:
	set_storage_area(area)

func set_storage_area(area: Rect2) -> void:
	if not area.position.is_finite() or not area.size.is_finite() or not area.has_area(): return
	_spawn_area = area
	_build_storage_slots()
	_layout_inventory()
	_layout_pending()
	queue_redraw()

func _storage_resized() -> void:
	_props.set_bounds(Rect2(Vector2.ZERO,size))
	_return_free_cards()

func _storage_ids(kind: String) -> Array[String]:
	var result: Array[String] = []
	if _rules == null: return result
	if kind == "module":
		for entry: Dictionary in _rules.modules: result.append(str(entry.id))
	else:
		var definitions: Resource = _rules.context_definitions
		if definitions != null:
			for entry: Dictionary in definitions.entries:
				if str(entry.kind) == kind: result.append(str(entry.id))
	return result

func _build_storage_slots() -> void:
	_storage_sections.clear()
	_storage_slots.clear()
	var cell_width := _spawn_area.size.x / STACK_KINDS.size()
	for index in STACK_KINDS.size():
		var kind: String = STACK_KINDS[index]
		var dimensions := CardFace.minimum_card_size(kind)
		var stack_size := dimensions + Vector2(6, 8)
		var section := Rect2(_spawn_area.position + Vector2(index * cell_width + (cell_width - stack_size.x) * .5, (_spawn_area.size.y - stack_size.y) * .5) + STACK_LAYOUT[kind].offset, stack_size)
		if not _stack_surfaces.has(kind):
			var surface := StackSurface.new()
			surface.name = "CardStack" + kind.capitalize()
			surface.kind = kind
			surface.title = STACK_TITLES[kind]
			add_child(surface)
			move_child(surface, 0)
			_stack_surfaces[kind] = surface
		var surface: Control = _stack_surfaces[kind]
		surface.position = section.position
		surface.size = section.size
		surface.pivot_offset = dimensions * .5
		surface.rotation = deg_to_rad(STACK_LAYOUT[kind].angle)
		_storage_sections[kind] = surface.get_transform() * Rect2(Vector2.ZERO, surface.size)
		_props.register_prop("stack/" + kind, surface, Rect2(Vector2.ZERO, section.size), false, false)
		for id: String in _storage_ids(kind):
			_storage_slots[kind + "/" + id] = Rect2(section.position, dimensions)
	_refresh_stack_surfaces()

func _refresh_stack_surfaces() -> void:
	for kind: String in _stack_surfaces:
		var count := 0
		for card: Dictionary in _cards.values():
			if str(card.kind) == kind and bool(card.inventory_docked) and int(card.clipped_slot) < 0:
				count += _available(kind, str(card.id))
		var surface: Control = _stack_surfaces[kind]
		surface.quantity = count
		surface.highlighted = kind == _drop_kind
		surface.hovered = kind == _drop_stack
		surface.selected = kind == _focus_kind
		surface.queue_redraw()

func stack_faces() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind: String in STACK_KINDS:
		if _stack_surfaces.has(kind):
			var surface: Control = _stack_surfaces[kind]
			result.append({"source":surface, "key":"stack/" + kind, "owner":null, "visible":is_visible_in_tree()})
	return result

func stack_viewport_rect(kind: String) -> Rect2:
	var surface: Control = _stack_surfaces[kind]
	return surface.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, surface.size)

func stack_details(kind: String) -> Dictionary:
	var quantity := 0
	var types := 0
	for card: Dictionary in _cards.values():
		if str(card.kind) == kind and bool(card.inventory_docked) and int(card.clipped_slot) < 0:
			types += 1
			quantity += _available(kind, str(card.id))
	return {"kind":kind, "title":DeskLocalization.source_format("%s卡摞", [str(STACK_TITLES.get(kind, kind))], [0]), "body":DeskLocalization.source_format("单击下方卡片查看详情，拖到纸张槽位安装。\n共 %d 类，%d 张。", [types, quantity]), "count":quantity, "types":types}

func _stack_at(point: Vector2) -> String:
	for kind: String in _stack_surfaces:
		var surface: Control = _stack_surfaces[kind]
		var local := surface.get_global_transform_with_canvas().affine_inverse() * point
		if Rect2(Vector2.ZERO, surface.size).has_point(local): return kind
	return ""

func preview_drop(kind: String, point: Vector2) -> void:
	_drop_kind = kind if kind in STACK_KINDS else ""
	_drop_stack = kind if _stack_at(point) == kind else ""
	_refresh_stack_surfaces()

func clear_drop_preview() -> void:
	_drop_kind = ""
	_drop_stack = ""
	_refresh_stack_surfaces()

func configure_focus_input(to_desktop: Callable) -> void:
	_focus_point_mapper = to_desktop

func focus_stack(kind: String, host: Control, rect: Rect2) -> void:
	if _focus_host != host:
		clear_stack_focus()
		_focus_host = host
		_focus_scroll = ScrollContainer.new()
		_focus_scroll.name = "ExpandedMaterialStack"
		_focus_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_focus_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_focus_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
		host.add_child(_focus_scroll)
		_focus_grid = GridContainer.new()
		_focus_grid.add_theme_constant_override("h_separation", 8)
		_focus_grid.add_theme_constant_override("v_separation", 10)
		_focus_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_focus_scroll.add_child(_focus_grid)
	_focus_kind = kind
	_focus_rect = rect
	_focus_scroll.position = rect.position
	_focus_scroll.size = rect.size
	_focus_scroll.show()
	_refresh_stack_surfaces()
	_refresh_focus_list()

func clear_stack_focus() -> void:
	if is_instance_valid(_focus_scroll): _focus_scroll.queue_free()
	_focus_scroll = null
	_focus_grid = null
	_focus_host = null
	_focus_kind = ""
	_focus_signature = ""
	_selected_key = ""
	clear_drop_preview()

func focus_dragging() -> bool:
	if _focus_grid == null: return false
	for row: Node in _focus_grid.get_children():
		if row is StackCard and row._pressed: return true
	return false

func _focus_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _focus_kind in ["stance_token", "pragmatic_token"]:
		for resource: Dictionary in _design.get("resources", []):
			if str(resource.kind) != _focus_kind or int(resource.get("available", 0)) <= 0: continue
			var record: Dictionary = _rules.context_resource(str(resource.id)).duplicate(true)
			record.count = int(resource.available)
			result.append(record)
	else:
		for card: Dictionary in _cards.values():
			if str(card.kind) == _focus_kind and bool(card.inventory_docked) and int(card.clipped_slot) < 0:
				result.append(_physical_face_record(card))
	return result

func _refresh_focus_list() -> void:
	if _focus_grid == null: return
	var records := _focus_records()
	var signature := _focus_kind + str(_focus_rect.size)
	for record: Dictionary in records: signature += str(record.id) + ":" + str(record.count) + ";"
	if signature == _focus_signature: return
	_focus_signature = signature
	for child: Node in _focus_grid.get_children():
		_focus_grid.remove_child(child)
		child.queue_free()
	var token := _focus_kind in ["stance_token", "pragmatic_token"]
	var dimensions := Vector2(112, 100) if token else CardFace.minimum_card_size(_focus_kind)
	_focus_grid.columns = maxi(1, floori((_focus_rect.size.x - 12) / (dimensions.x + 8)))
	if records.is_empty():
		var empty := Label.new()
		empty.text = DeskLocalization.text("暂无可用材料\n收取传真后会放入对应卡摞。")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(maxf(100, _focus_rect.size.x - 18), 72)
		empty.add_theme_font_size_override("font_size", 15)
		empty.add_theme_color_override("font_color", Color("60664f"))
		_focus_grid.add_child(empty)
		return
	for record: Dictionary in records:
		var row := StackCard.new()
		row.name = "StackItem" + str(record.id).to_pascal_case()
		row.custom_minimum_size = dimensions
		row.size = dimensions
		row.record = record
		row.font = get_theme_font("font", "Label")
		row.overlay = _focus_host
		row.token = token
		row.face = ResourceGraphic.new() if token else CardFace.new()
		row.face.size = dimensions
		row.add_child(row.face)
		if token:
			row.face.configure(record)
			var count := Label.new()
			count.text = "×%d" % int(record.count)
			count.position = Vector2(dimensions.x - 30, 3)
			count.add_theme_color_override("font_color", Color("373d33"))
			count.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(count)
		else:
			row.face.configure(record, row.font)
			row.face.set_selected(_selected_key == str(record.kind) + "/" + str(record.id))
		row.chosen.connect(_select_expanded.bind(str(record.kind), str(record.id)))
		row.dragged.connect(func(point: Vector2): preview_drop(str(record.kind), _map_focus_point(point)))
		row.dropped.connect(_drop_expanded.bind(str(record.kind), str(record.id)))
		row.drag_cancelled.connect(clear_drop_preview)
		_focus_grid.add_child(row)

func _map_focus_point(point: Vector2) -> Vector2:
	return _focus_point_mapper.call(point) if _focus_point_mapper.is_valid() else point

func _select_expanded(kind: String, id: String) -> void:
	_selected_key = kind + "/" + id
	for row: Node in _focus_grid.get_children():
		if row is StackCard and not row.token:
			row.face.set_selected(str(row.record.kind) + "/" + str(row.record.id) == _selected_key)
	item_clicked.emit(kind, id)

func _drop_expanded(point: Vector2, kind: String, id: String) -> void:
	var desktop_point := _map_focus_point(point)
	clear_drop_preview()
	if kind in ["stance_token", "pragmatic_token"]:
		item_dropped.emit(kind, id, desktop_point)
		return
	if _stack_at(desktop_point) == kind:
		store_item(kind, id)
		return
	var key := _free_key(kind, id)
	var origin: Vector2 = _cards[key].node.global_position
	place_existing_item(kind, id, desktop_point)
	_cards[key].return_position = origin
	_cards[key].return_docked = true
	item_dropped.emit(kind, id, desktop_point)
	if _cards.has(key):
		_cards[key].erase("return_position")
		_cards[key].erase("return_docked")
	_layout_inventory()

func store_item(kind: String, id: String) -> bool:
	if kind in ["stance_token", "pragmatic_token"]: return _available(kind, id) > 0
	if not request_item(kind, id): return false
	var key := _free_key(kind, id)
	_cards[key].inventory_docked = true
	_cards[key].erase("return_position")
	_cards[key].erase("return_docked")
	_layout_inventory()
	return true

func _inventory_position(kind: String, index: int, item_size: Vector2) -> Vector2:
	var ids := _storage_ids(kind)
	if index < 0 or index >= ids.size(): return _spawn_area.position
	var slot: Rect2 = _storage_slots.get(kind+"/"+ids[index],Rect2(_spawn_area.position,item_size))
	return slot.get_center()-item_size*0.5

func _resize_card(card: Dictionary, target: Vector2) -> void:
	var node: Control = card.node
	node.size = target
	node.pivot_offset = target*0.5
	card.paper.size = target
	card.graphic.position = Vector2(4,24)
	card.graphic.size = target-Vector2(8,28)
	if card.has("face"):
		card.face.size = target
		card.face.configure(_physical_face_record(card),get_theme_font("font","Label"))
		card.face.visible = not bool(card.inventory_docked)
	card.count.position = Vector2(maxf(0,target.x-24),1)
	card.count.size = Vector2(24,16)
	card.title.position = Vector2(3,2)
	card.title.size = Vector2(maxf(0,target.x-20),23)
	card.title.add_theme_font_size_override("font_size",9)
	card.hover.position = Vector2(-5,-5)
	card.hover.size = target+Vector2(10,10)
	card.hover.material.set_shader_parameter("object_size",target)
	card.hover.material.set_shader_parameter("padding",Vector2(5,5))
	card.hover.material.set_shader_parameter("rect_origin",Vector2(5,5))

func _park_card(key: String) -> void:
	if not _cards.has(key): return
	var card: Dictionary = _cards[key]
	if int(card.get("clipped_slot", -1)) >= 0: return
	var target := CardFace.minimum_card_size(str(card.kind))
	_resize_card(card, target)
	for row: Dictionary in _design.get("event_materials", []):
		var event_key := _event_key(row)
		if str(row.get("kind", "")) == str(card.kind) and str(row.get("id", "")) == str(card.id) and bool(row.get("claimed", false)) and _event_positions.has(event_key):
			var point: Vector2 = _event_positions[event_key]
			card.node.position = point - target * .5
			card.inventory_docked = _stack_at(get_global_transform_with_canvas() * point) == str(card.kind)
			_event_positions.erase(event_key)
	if bool(card.inventory_docked):
		var slot: Rect2 = _storage_slots.get(str(card.kind) + "/" + str(card.id), Rect2(_spawn_area.position, target))
		card.node.position = slot.get_center() - target * .5
		card.node.rotation = _stack_surfaces[str(card.kind)].rotation
		# The top inventory card supplies input beneath the shared stack face.
		card.node.visible = key == _top_inventory_card(str(card.kind))
	else:
		card.node.show()
	card.face.visible = not bool(card.inventory_docked)
	card.inventory_position = card.node.position
	_props.register_prop(key, card.node, Rect2(Vector2.ZERO, target), false, true)
	_moved(key, card.node.global_position)

func _top_inventory_card(kind: String) -> String:
	for key: String in _cards:
		var card: Dictionary = _cards[key]
		if str(card.kind) == kind and bool(card.inventory_docked) and int(card.clipped_slot) < 0:
			return key
	return ""

func _physical_face_record(card: Dictionary) -> Dictionary:
	var sources: Array = []
	if str(card.kind) == "module":
		for source: Dictionary in _design.get("inventory_sources",[]):
			if str(source.get("kind","")) == "module" and str(source.get("id","")) == str(card.id): sources.append(source)
	else:
		for resource: Dictionary in _design.get("resources",[]):
			if str(resource.get("id","")) == str(card.id): sources = resource.get("source_records",[])
	var labels := PackedStringArray()
	for source: Dictionary in sources:
		var label := str(source.get("source_instance_id",""))
		if not label.is_empty() and label not in labels: labels.append(label)
	var quantity := 1 if int(card.get("clipped_slot",-1)) >= 0 else _available(str(card.kind),str(card.id))
	return {"kind":str(card.kind),"id":str(card.id),"title":_title(str(card.kind),str(card.id)),"count":quantity,"source_label":" · ".join(labels),"source_records":sources.duplicate(true)}

func _layout_inventory() -> void:
	# Inventory refreshes must not interrupt a card already under the pointer.
	var held := str(_props.inspection().pressed) if _props != null else ""
	for key: String in _cards:
		if key != held: _park_card(key)
	_refresh_stack_surfaces()
	_refresh_focus_list()

func _return_free_cards() -> void:
	if _props == null: return
	_props.cancel_drag(&"return_to_storage")
	if _focus_grid != null:
		for row: Node in _focus_grid.get_children():
			if row is StackCard: row.cancel_drag()
	clear_drop_preview()
	_layout_inventory()

func return_to_inventory(kind: String, id: String) -> void:
	# The design editor owns an accepted item; its desktop proxy must not cover it.
	var key := kind + "/" + id
	var remaining := _available(kind,id)
	if remaining > 0:
		_return_remaining(key, remaining)
		return
	if _cards.has(key): _remove(key)

func _return_remaining(key: String, count: int) -> void:
	if not _cards.has(key): return
	var card: Dictionary = _cards[key]
	card.count.text = "×%d" % count
	# The accepted unit belongs to the slot; remaining stock stays at the drag origin.
	if card.get("return_position") is Vector2:
		card.node.global_position = card.return_position
		card.inventory_docked = bool(card.get("return_docked", false))
	_park_card(key)

func _available(kind: String, id: String) -> int:
	if kind != "module":
		for resource: Dictionary in _design.get("resources",[]):
			if str(resource.id)==id and str(resource.kind)==kind: return int(resource.get("available",0))
		return 0
	var inventory: Dictionary = _design.get("available_module_inventory",_design.get("module_inventory",{}))
	var reserved := 0
	for installed in _design.get("module_slots",[]):
		if str(installed)==id: reserved+=1
	return maxi(0,int(inventory.get(id,0))-reserved)

func _free_key(kind: String, id: String) -> String:
	for key in _cards:
		var card: Dictionary = _cards[key]
		if card.kind==kind and card.id==id and int(card.get("clipped_slot",-1))<0: return str(key)
	return ""

func _clipped_key(slot: int) -> String:
	for key in _cards:
		if int(_cards[key].get("clipped_slot",-1))==slot: return str(key)
	return ""

func _installed(id: String) -> bool:
	return id in _design.get("module_slots",[])

func sync_state(state: Dictionary) -> void:
	if _rules == null: return
	var seed := int(state.get("seed",0))
	if seed != _seed:
		clear_cards()
		_seed = seed
	_design = state.get("design_state",{}).duplicate(true)
	var wanted := {}
	var inventory: Dictionary = _design.get("module_inventory",{})
	for id in inventory:
		var count := _available("module",str(id))
		if count<=0: continue
		var key := _free_key("module",str(id))
		if key.is_empty():
			request_item("module",str(id))
			key=_free_key("module",str(id))
		if not key.is_empty():
			wanted[key]=true
			_cards[key].count.text="×%d" % count
	for resource: Dictionary in _design.get("resources",[]):
		var kind := str(resource.kind)
		var id := str(resource.id)
		if kind in ["stance_token","pragmatic_token"]: continue
		if int(resource.get("available",0))<=0: continue
		var key := _free_key(kind,id)
		if key.is_empty():
			request_item(kind,id)
			key=_free_key(kind,id)
		if not key.is_empty():
			wanted[key]=true
			_cards[key].count.text="×%d" % int(resource.available)
	# Keep the same paper alive while an accepted clamp is being attached.
	var slots: Array = _design.get("module_slots",[])
	for slot in slots.size():
		var id := str(slots[slot])
		if id.is_empty(): continue
		var key := _clipped_key(slot)
		if key.is_empty() or _cards[key].id!=id:
			key=_free_key("module",id)
			if key.is_empty():
				request_item("module",id,true)
				key=_free_key("module",id)
		if not key.is_empty(): wanted[key]=true
	for key in _cards.keys():
		if not wanted.has(key): _remove(key)
	_sync_pending_materials()
	_layout_inventory()

func clamp_module(id: String, slot: int, parent: Control, anchor: Vector2) -> bool:
	if parent==null or not _installed(id): return false
	var attached := _clipped_key(slot)
	if not attached.is_empty(): return _cards[attached].id==id
	var key := _free_key("module",id)
	if key.is_empty():
		if not request_item("module",id,true): return false
		key=_free_key("module",id)
	var card: Dictionary = _cards[key]
	var node: Control = card.node
	card.clipped_slot=slot
	card.inventory_docked=false
	_resize_card(card,Vector2(112,94))
	node.show()
	card.anchor=anchor
	var global_scale := node.get_global_transform_with_canvas().get_scale()
	node.reparent(parent,true)
	node.scale=global_scale/parent.get_global_transform_with_canvas().get_scale()
	node.rotation=deg_to_rad(float(slot-2)*1.3)
	node.position=anchor
	if parent.has_method("bring_front"): parent.bring_front()
	card.count.text=""
	_props.register_prop(key,node,Rect2(Vector2.ZERO,node.size),false,true)
	_moved(key,node.global_position)
	return true

func _unclamp(key: String) -> void:
	var card: Dictionary = _cards[key]
	var slot := int(card.clipped_slot)
	var node: Control = card.node
	card.clipped_slot=-1
	var rotation := node.get_global_transform().get_rotation()
	var global_scale := node.get_global_transform().get_scale()
	node.reparent(self,true)
	node.rotation=rotation-get_global_transform().get_rotation()
	node.scale=global_scale/get_global_transform().get_scale()
	release_module.emit(slot,card.id)

func remember_event_position(record: Dictionary, point: Vector2) -> void:
	if not point.is_finite(): return
	_event_positions[_event_key(record)] = get_global_transform_with_canvas().affine_inverse()*point

func discard_event_position(record: Dictionary) -> void:
	_event_positions.erase(_event_key(record))

func _event_key(record: Dictionary) -> String:
	return "%s/%s/%s" % [str(record.get("instance_id", "")), str(record.get("kind", "")), str(record.get("id", ""))]

func _sync_pending_materials() -> void:
	var wanted := {}
	for row: Dictionary in _design.get("event_materials", []):
		var key := _event_key(row)
		if row.get("requested", false) and row.get("pending", false):
			wanted[key] = true
			if not _pending_cards.has(key):
				var slip := RewardSlip.new()
				slip.name = "SealedMaterial"+str(_pending_cards.size())
				add_child(slip)
				slip.size = Vector2(96,68)
				slip.configure(row, self, theme)
				slip.set_interaction_enabled(false)
				_pending_cards[key] = slip
		elif row.get("claimed", false) and _pending_cards.has(key):
			var material_key := str(row.kind)+"/"+str(row.id)
			if _cards.has(material_key):
				_park_card(material_key)
	for key in _pending_cards.keys():
		if not wanted.has(key):
			_pending_cards[key].queue_free()
			_pending_cards.erase(key)
	_layout_pending()

func _layout_pending() -> void:
	var area: Rect2 = _storage_sections.get("pending",Rect2(_spawn_area.position,Vector2(200,64)))
	var index := 0
	for key: String in _pending_cards:
		var slip: Control = _pending_cards[key]
		slip.size = Vector2(minf(96,maxf(24,area.size.x/3.0)),maxf(24,area.size.y-20))
		slip.position = area.position+Vector2((index%3)*area.size.x/3.0,18)
		index += 1

func request_item(kind: String, id: String, installed: bool=false) -> bool:
	if not INVENTORIES.has(kind) or (_available(kind,id)<=0 and not (installed and kind=="module" and _installed(id))): return false
	var key := _free_key(kind,id)
	if not key.is_empty():
		_raise(key)
		return true
	key=kind+"/"+id
	while _cards.has(key): key+="/copy"
	_seen[kind+"/"+id]=true
	var node := Control.new()
	node.name = "Material" + str(_cards.size())
	node.mouse_filter = MOUSE_FILTER_IGNORE
	node.size = Vector2(144,78) if kind=="topic" else Vector2(112,82)
	var siblings := 0
	for existing: Dictionary in _cards.values():
		if existing.kind==kind and int(existing.get("clipped_slot",-1))<0: siblings+=1
	node.position = _inventory_position(kind, siblings, node.size)
	node.rotation = deg_to_rad(float((_cards.size()%5)-2)*2)
	node.pivot_offset = node.size*.5
	add_child(node)
	var paper := TextureRect.new()
	paper.texture = Paper
	if kind in ["stance_token","pragmatic_token"]:
		var atlas := AtlasTexture.new()
		atlas.atlas=load("res://assets/image/textures/studio/desk/metal_resources.png")
		var cell := Vector2(0,1) if kind=="group" else (Vector2(1,0) if kind=="pragmatic_token" else Vector2.ZERO)
		atlas.region=Rect2(cell*Vector2(atlas.atlas.get_size())*.5,Vector2(atlas.atlas.get_size())*.5)
		paper.texture=atlas
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.size = node.size
	paper.mouse_filter = MOUSE_FILTER_IGNORE
	if _ink != null and kind in ["module","topic"]: paper.material = _ink.duplicate()
	node.add_child(paper)
	var marks := RewardSlip.CardMarks.new()
	marks.kind = kind
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.add_child(marks)
	paper.modulate = {"language":Color("e2e7dc"),"group":Color("e4d6b6"),"module":Color("dddbe5"),"topic":Color("eee1ba")}.get(kind,Color.WHITE)
	var shadow := Shade.new()
	shadow.z_index = -1
	node.add_child(shadow)
	shadow.configure(paper.texture)
	var graphic: Control = NeuronGraphic.new() if kind=="module" else ResourceGraphic.new()
	graphic.name="Graphic"
	graphic.mouse_filter=MOUSE_FILTER_IGNORE
	graphic.position=Vector2(5,32) if kind=="module" else Vector2.ZERO
	graphic.size=Vector2(86,78) if kind=="module" else node.size
	node.add_child(graphic)
	if kind=="module":
		graphic.configure(id,str(_rules.find("modules",id).get("kernel_id","stance")))
		graphic.grow()
	else:
		graphic.configure(_rules.context_resource(id))
	var title := Label.new()
	title.name = "StoredMaterialTitle"
	title.text = _title(kind,id)
	title.position = Vector2(6,3)
	title.size = Vector2(62,30)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size",11)
	title.add_theme_color_override("font_color",Color("343a30"))
	title.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_child(title)
	var count := Label.new()
	count.position = Vector2(69,3)
	count.add_theme_font_size_override("font_size",12)
	count.add_theme_color_override("font_color",Color("343a30"))
	count.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_child(count)
	var rim := TextureRect.new()
	rim.texture = paper.texture
	rim.position = Vector2(-7,-7)
	rim.size = node.size+Vector2(14,14)
	rim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rim.mouse_filter = MOUSE_FILTER_IGNORE
	rim.z_index = -2
	var material := ShaderMaterial.new()
	material.shader = Hover
	material.set_shader_parameter("source_texture",paper.texture)
	material.set_shader_parameter("object_size",node.size)
	material.set_shader_parameter("padding",Vector2(7,7))
	material.set_shader_parameter("rect_origin",Vector2(7,7))
	material.set_shader_parameter("band_width",6.0)
	rim.material = material
	rim.hide()
	node.add_child(rim)
	var face := CardFace.new()
	face.name = "PhysicalMaterialCardFace"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(face)
	paper.hide()
	marks.hide()
	graphic.hide()
	title.hide()
	count.hide()
	shadow.hide()
	_cards[key] = {"face":face,"node":node,"paper":paper,"shadow":shadow,"hover":rim,"count":count,"title":title,"kind":kind,"id":id,"clipped_slot":-1,"graphic":graphic,"inventory_docked":true,"inventory_position":node.position,"inventory_index":siblings,"event_placed":false,"card_style":{"language":"ruled_language_card","group":"ochre_group_card","module":"graph_patch_card","topic":"horizontal_topic_card"}.get(kind,"material_card")}
	node.tooltip_text = ""
	count.text = "×%d" % _available(kind,id)
	_props.register_prop(key,node,Rect2(Vector2.ZERO,node.size),false,true)
	_park_card(key)
	return true

func place_existing_item(kind: String, id: String, point: Vector2) -> bool:
	if not point.is_finite() or not request_item(kind,id): return false
	var key := _free_key(kind,id)
	_cards[key].node.position = get_global_transform_with_canvas().affine_inverse() * point - _cards[key].node.size * .5
	_cards[key].inventory_docked = _stack_at(point) == kind
	_park_card(key)
	_refresh_stack_surfaces()
	_refresh_focus_list()
	return true

func _title(kind: String, id: String) -> String:
	var entry: Dictionary = _rules.find("modules",id) if kind=="module" else _rules.context_resource(id)
	return str(entry.get("title",id))

func _clicked(key: StringName) -> void:
	if String(key).begins_with("stack/"):
		stack_clicked.emit(String(key).trim_prefix("stack/"))
		return
	if _cards.has(String(key)):
		var card: Dictionary = _cards[String(key)]
		if bool(card.inventory_docked):
			stack_clicked.emit(str(card.kind))
		else:
			_raise(String(key))
			item_clicked.emit(card.kind,card.id)

func _raise(key: String) -> void:
	var node: Control = _cards[key].node
	node.get_parent().move_child(node,node.get_parent().get_child_count()-1)
	_props.unregister_prop(key)
	_props.register_prop(key,node,Rect2(Vector2.ZERO,node.size),false,true)

func _card_moved(key: StringName, point: Vector2) -> void:
	if _cards.has(String(key)):
		var was_docked := bool(_cards[String(key)].inventory_docked)
		if not _cards[String(key)].has("return_docked"):
			_cards[String(key)].return_docked = was_docked
		_cards[String(key)].inventory_docked = false
		_cards[String(key)].face.show()
		if was_docked: _layout_inventory()
		preview_drop(str(_cards[String(key)].kind), _props._input_diagnostic.last_point)
	_moved(key, point)

func _moved(key: StringName, _point: Vector2) -> void:
	if not _cards.has(String(key)): return
	var card: Dictionary = _cards[String(key)]
	if int(card.get("clipped_slot",-1))>=0 and card.node.position.distance_to(card.anchor)>16:
		_unclamp(String(key))
	var paper: TextureRect = card.paper
	var shadow: DeskObjectShadow = card.shadow
	var center := paper.get_global_transform()*(paper.size*.5)
	shadow.shadow_offset = paper.get_global_transform().affine_inverse().basis_xform((center-_light.global_position).normalized()*Vector2(4,4).length())
	shadow.shadow_blur = 3
	shadow.shadow_opacity = .2
	shadow.ao_strength = .12
	shadow.sync_from(paper)
	shadow.apply_parameters()
	if paper.material is ShaderMaterial: paper.material.set_shader_parameter("light_position",_light.global_position)

func _hovered(key: StringName) -> void:
	var hovered_stack := String(key).trim_prefix("stack/")
	if _cards.has(String(key)) and bool(_cards[String(key)].inventory_docked):
		hovered_stack = str(_cards[String(key)].kind)
	for id in _cards:
		_cards[id].hover.hide()
		if _cards[id].has("face"): _cards[id].face.set_hovered(id == String(key) and _enabled)
	for kind: String in _stack_surfaces:
		_stack_surfaces[kind].hovered = hovered_stack == kind
		_stack_surfaces[kind].queue_redraw()

func _remove(key: String) -> void:
	_props.unregister_prop(key)
	_cards[key].node.queue_free()
	_cards.erase(key)

func clear_cards() -> void:
	clear_stack_focus()
	for key in _cards.keys(): _remove(key)
	_seen.clear()
	for slip in _pending_cards.values(): slip.queue_free()
	_pending_cards.clear()
	_event_positions.clear()

func _released(key: StringName, point: Vector2, origin: Vector2) -> void:
	clear_drop_preview()
	if _cards.has(String(key)):
		var card: Dictionary = _cards[String(key)]
		if _stack_at(point) == str(card.kind):
			store_item(str(card.kind), str(card.id))
			return
		card.return_position = origin
		item_dropped.emit(card.kind,card.id,point)
		# The authority callback may remove or clip the item before it returns.
		if _cards.has(String(key)):
			_cards[String(key)].erase("return_position")
			_cards[String(key)].erase("return_docked")
		_layout_inventory()

func _process(_delta: float) -> void:
	if _light != null and not _light.global_position.is_equal_approx(_last_light):
		_last_light = _light.global_position
		for id in _cards: _moved(id,_cards[id].node.global_position)

func handles_viewport_point(viewport_point: Vector2) -> bool:
	return _enabled and is_visible_in_tree() and _props != null and _props._hit_prop(viewport_point) != &""

func hover_info(viewport_point: Vector2) -> Dictionary:
	if not _enabled or not is_visible_in_tree(): return {}
	var key := String(_props._hit_prop(viewport_point))
	if key.begins_with("stack/"):
		var details := stack_details(key.trim_prefix("stack/"))
		details.gesture = "单击展开卡摞"
		return details
	if not _cards.has(key): return {}
	return details_for_item(str(_cards[key].kind),str(_cards[key].id))

func tutorial_drag_cards(kinds: Array[String], preferred := "", preferred_anchor := Vector2(0.5, 0.5)) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not _enabled or not is_visible_in_tree(): return candidates
	var held := String(_props._pressed)
	for index in range(_props._order.size() - 1, -1, -1):
		var key := String(_props._order[index])
		if not _cards.has(key): continue
		# A held card owns the guide until the player releases it.
		if not held.is_empty() and key != held: continue
		var card: Dictionary = _cards[key]
		if card.kind not in kinds or int(card.get("clipped_slot", -1)) >= 0: continue
		if not card.node.is_visible_in_tree() or _available(card.kind, card.id) <= 0: continue
		var anchor := preferred_anchor if key == preferred else Vector2(0.5, 0.5)
		if held.is_empty():
			var exposed := false
			var probes := [anchor, Vector2(0.5, 0.5)]
			for y in [0.05, 0.5, 0.95]:
				for x in [0.05, 0.5, 0.95]: probes.append(Vector2(x, y))
			for uv: Vector2 in probes:
				var point: Vector2 = card.node.get_global_transform_with_canvas() * (card.node.size * uv)
				if String(_props._hit_prop(point)) == key:
					anchor = uv
					exposed = true
					break
			if not exposed: continue
		var candidate := {"key":key, "node":card.node, "kind":card.kind, "id":card.id, "anchor":anchor, "dragging":_props._dragging}
		if key == preferred: candidates.push_front(candidate)
		else: candidates.append(candidate)
	return candidates

func details_for_item(kind: String,id: String) -> Dictionary:
	var key := kind+"/"+id
	var card: Dictionary = _cards.get(key, {"kind":kind, "id":id, "clipped_slot":-1, "inventory_docked":true})
	var definition: Dictionary = _rules.find("modules",card.id) if card.kind == "module" else _rules.context_resource(card.id)
	var installed: bool = int(card.get("clipped_slot",-1)) >= 0
	var details := {"kind":card.kind,"id":card.id,"title":str(definition.get("title",card.id)),
		"count":_available(card.kind,card.id),"description":str(definition.get("description","")),
		"status":"已安装" if installed else ("收纳中" if bool(card.inventory_docked) else "桌面卡牌"),
		"gesture":"拖到回形针安装；拖出回形针移除" if card.kind == "module" else "拖到对应空槽安装"}
	var face_record := _physical_face_record(card)
	details.source_label = str(face_record.get("source_label",""))
	details.source_records = face_record.get("source_records",[]).duplicate(true)
	if str(card.id) == "module_boundary": details.unlock_hint = "安装后增加一个语言槽"
	elif str(card.id) == "module_relation": details.unlock_hint = "安装后增加一个人群槽"
	if kind in ["stance_token", "pragmatic_token"]: details.gesture = "拖到对应坐标轴使用"
	return details

func inspection() -> Dictionary:
	var items := []
	for card in _cards.values():
		items.append({"kind":card.kind,"id":card.id,"rect":card.node.get_global_rect(),"count":card.count.text,"visible":card.node.is_visible_in_tree(),"instance_id":card.node.get_instance_id(),"clipped_slot":int(card.get("clipped_slot",-1)),"parent":str(card.node.get_parent().get_path()),"graphic":card.graphic.inspection(),"global_scale":card.node.get_global_transform_with_canvas().get_scale(),"size":card.node.size,"inventory_docked":bool(card.get("inventory_docked",false)),"inventory_position":card.get("inventory_position",Vector2.ZERO),"card_style":str(card.face.inspection().shape) if card.has("face") else card.get("card_style", "material_card"),"face":card.face.inspection() if card.has("face") else {}})
	return {"items":items,"spawn_area":_spawn_area,"storage_area":_spawn_area,"storage_mode":"fixed_typed_stacks","storage_sections":_storage_sections.duplicate(),"storage_slots":_storage_slots.duplicate(),"returns_failed_drop":false,"free_placement":true,"pending":_pending_cards.values().map(func(slip): return slip.inspection()),"focused_stack":_focus_kind,"expanded_count":_focus_records().size(),"drop_kind":_drop_kind,"hovered_drop_stack":_drop_stack,"grants_inventory":false,"writes_layout":false,"interaction":_props.inspection()}

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_layout_inventory()
		queue_redraw()
