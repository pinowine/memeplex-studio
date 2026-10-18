class_name DeskArchiveBrowser
extends Control

signal focus_changed(focused: bool)
signal event_requested(event: Dictionary)

const Contents := preload("res://scenes/demo/desk_archive_contents.tscn")
const PaperStyle := preload("res://scripts/demo/desk_paper_style.gd")

@export var focus_duration: float = 0.28
@export var flip_duration: float = 0.18

var _folder: TextureRect
var _textures: Dictionary = {}
var _view := Rect2(0, 0, 1280, 800)
var _target := Rect2()
var _saved_pose: Dictionary = {}
var _memes: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _tab: String = "memes"
var _selected := {"memes":"", "events":""}
var _focused: bool = false
var _closing: bool = false
var _blocked: bool = false
var _mix: float = 0.0
var _flips: int = 0
var _built: bool = false
var _focus_tween: Tween
var _flip_tween: Tween
var _paused_tweens: Array[Tween] = []
var _ui: Control
var _pages: Control
var _shade: ColorRect
var _list: ItemList
var _details: RichTextLabel
var _title: Label
var _empty: Label
var _listing_title: Label
var _notice: Label
var _view_button: Button
var _meme_tab: Button
var _event_tab: Button
var _close_button: Button
var _flip_sheet: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = _view.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = false
	z_index = 26
	_build()
	_layout()
	_refresh()


func configure(textures: Dictionary, print_theme: Theme = null) -> void:
	_textures = textures.duplicate()
	if print_theme != null: theme = print_theme
	if _built:
		_flip_sheet.texture = _textures.get("paper", _textures.get("bookgrain")) as Texture2D
		_layout()


func bind_folder(node: TextureRect) -> void:
	if _focused or _closing: _restore_folder()
	_folder = node
	_saved_pose = {}
	if is_instance_valid(_folder) and _textures.get("closed") is Texture2D:
		_folder.texture = _textures.closed


func layout_browser(viewport_rect: Rect2) -> void:
	_view = viewport_rect
	position = viewport_rect.position
	size = viewport_rect.size
	_layout()
	if _focused or _closing: _apply_pose(_mix)


func sync_state(snapshot: Dictionary) -> void:
	# Group only observed variants. A catalog is never a discovery source.
	_memes = []
	_events = []
	var records: Dictionary = snapshot.get("family_records", {}) if snapshot.get("family_records", {}) is Dictionary else {}
	var lineage: Array = snapshot.get("lineage", []) if snapshot.get("lineage", []) is Array else []
	var groups: Dictionary = {}
	var variant_ids: Dictionary = {}
	for item in lineage:
		if not item is Dictionary: continue
		var family_id := str(item.get("family_id", ""))
		var variant_id := str(item.get("id", ""))
		if family_id.is_empty() or variant_id.is_empty() or variant_ids.has(variant_id): continue
		variant_ids[variant_id] = true
		if not groups.has(family_id): groups[family_id] = []
		groups[family_id].append(item.duplicate(true))
	for family_id in groups:
		var family: Dictionary = records.get(family_id, {}) if records.get(family_id, {}) is Dictionary else {}
		_memes.append({"id":str(family_id), "family":family.duplicate(true), "variants":groups[family_id].duplicate(true)})
	var event_ids: Dictionary = {}
	var happened: Array = snapshot.get("events", []) if snapshot.get("events", []) is Array else []
	for item in happened:
		if not item is Dictionary: continue
		var event_id := str(item.get("instance_id", ""))
		if event_id.is_empty() or event_ids.has(event_id): continue
		event_ids[event_id] = true
		_events.append(item.duplicate(true))
	for tab in ["memes", "events"]:
		var rows: Array[Dictionary] = _memes if tab == "memes" else _events
		if not _has_id(rows, str(_selected[tab])):
			_selected[tab] = str(rows[0].get("id", rows[0].get("instance_id", ""))) if not rows.is_empty() else ""
	_refresh()


func focus() -> bool:
	if not _built or not is_instance_valid(_folder) or _focused or _closing or _blocked: return false
	if not _textures.get("open") is Texture2D: return false
	_saved_pose = {"position":_folder.position, "size":_folder.size, "rotation":_folder.rotation, "texture":_folder.texture, "z_index":_folder.z_index, "z_as_relative":_folder.z_as_relative, "visible":_folder.visible, "mouse_filter":_folder.mouse_filter}
	_folder.texture = _textures.open
	_folder.show()
	_folder.z_as_relative = false
	_folder.z_index = 27
	_folder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_focused = true
	_mix = 0.0
	_refresh()
	focus_changed.emit(true)
	_animate_focus(1.0)
	return true


func close() -> bool:
	if not _focused or _closing or _blocked: return false
	_closing = true
	_refresh()
	_animate_focus(0.0)
	return true


func select_tab(id: String) -> bool:
	if id == "meme": id = "memes"
	if id == "event": id = "events"
	if id not in ["memes", "events"] or _blocked or _closing: return false
	if id == _tab: return true
	_tab = id
	_refresh()
	_flip()
	return true


func select_item(id: String) -> bool:
	if _blocked or _closing: return false
	var rows: Array[Dictionary] = _memes if _tab == "memes" else _events
	if not _has_id(rows, id): return false
	if _selected[_tab] == id: return true
	_selected[_tab] = id
	_refresh()
	_flip()
	return true


func request_selected_event() -> bool:
	if not _focused or _closing or _blocked or _mix != 1.0 or _tab != "events": return false
	var record := _event_by_id(str(_selected.events))
	if record.is_empty(): return false
	# Presentation signals carry their own copy, including unread occurrences.
	event_requested.emit(record.duplicate(true))
	return true


func set_notice(message: String) -> void:
	if _built: _notice.text = message


func set_interaction_blocked(blocked: bool) -> void:
	if _blocked == blocked: return
	_blocked = blocked
	if blocked:
		_paused_tweens.clear()
		for tween in [_focus_tween, _flip_tween]:
			if tween != null and tween.is_valid() and tween.is_running():
				tween.pause()
				_paused_tweens.append(tween)
	else:
		for tween in _paused_tweens:
			if tween != null and tween.is_valid() and tween.get_loops_left() != 0: tween.play()
		_paused_tweens.clear()
	_refresh()


func handle_key(event: InputEventKey) -> bool:
	if not _focused or _blocked or not event.pressed or event.echo: return false
	if event.keycode == KEY_ESCAPE:
		close()
		return true
	return false


func reset_browser() -> void:
	var was_focused := _focused or _closing
	if _focus_tween != null and _focus_tween.is_valid(): _focus_tween.kill()
	if _flip_tween != null and _flip_tween.is_valid(): _flip_tween.kill()
	_paused_tweens.clear()
	_restore_folder()
	_focused = false
	_closing = false
	_blocked = false
	_mix = 0.0
	_memes = []
	_events = []
	_selected = {"memes":"", "events":""}
	_tab = "memes"
	_refresh()
	if was_focused: focus_changed.emit(false)


func inspection() -> Dictionary:
	return {"focused":_focused, "closing":_closing, "blocked":_blocked, "focus_progress":_mix, "tab":_tab, "selected":_selected.duplicate(), "families":_memes.duplicate(true), "events":_events.duplicate(true), "family_count":_memes.size(), "event_count":_events.size(), "page_flips":_flips, "folder_bound":is_instance_valid(_folder), "folder_rect":_folder.get_global_rect() if is_instance_valid(_folder) else Rect2(), "target_rect":_target, "left_rect":_list.get_global_rect() if _built else Rect2(), "right_rect":_details.get_global_rect() if _built else Rect2(), "details_title":_title.text if _built else "", "details_text":_details.text if _built else "", "plain_text":not _details.bbcode_enabled if _built else true, "read_only":true, "notice":_notice.text if _built else "", "economic_calls":0, "save_calls":0}


func _build() -> void:
	_ui = Contents.instantiate()
	add_child(_ui)
	_pages = _ui.get_node("Pages")
	_shade = _ui.get_node("Shade")
	_list = _pages.get_node("Records")
	_details = _pages.get_node("Details")
	_title = _pages.get_node("DetailsTitle")
	_empty = _pages.get_node("Empty")
	_listing_title = _pages.get_node("ListingTitle")
	_notice = _pages.get_node("Notice")
	_view_button = _pages.get_node("ViewEvent")
	_meme_tab = _pages.get_node("MemeTab")
	_event_tab = _pages.get_node("EventTab")
	for tab in [_meme_tab, _event_tab]:
		tab.add_theme_color_override("font_pressed_color", Color("2e2b24"))
		tab.add_theme_color_override("font_hover_pressed_color", Color("2e2b24"))
	_close_button = _pages.get_node("Close")
	_flip_sheet = _pages.get_node("FlipSheet")
	_meme_tab.pressed.connect(func() -> void: select_tab("memes"))
	_event_tab.pressed.connect(func() -> void: select_tab("events"))
	_close_button.pressed.connect(close)
	_view_button.pressed.connect(request_selected_event)
	_list.item_selected.connect(_on_item_selected)
	_flip_sheet.texture = _textures.get("paper", _textures.get("bookgrain")) as Texture2D
	_built = true
	PaperStyle.apply_buttons(self)


func _has_id(rows: Array[Dictionary], id: String) -> bool:
	for row in rows:
		if str(row.get("id", row.get("instance_id", ""))) == id: return true
	return false


func _event_by_id(id: String) -> Dictionary:
	for event in _events:
		if str(event.instance_id) == id: return event
	return {}


func _on_item_selected(index: int) -> void:
	if index >= 0 and index < _list.item_count: select_item(str(_list.get_item_metadata(index)))


func _refresh() -> void:
	if not _built: return
	_ui.visible = _focused or _closing
	_pages.modulate.a = _mix
	_shade.color.a = 0.38 * _mix
	_list.clear()
	var rows: Array[Dictionary] = _memes if _tab == "memes" else _events
	for row in rows:
		var id := str(row.get("id", row.get("instance_id", "")))
		var text := ""
		if _tab == "memes":
			text = "%s  ·  %d 个版本" % [str(row.family.get("anchor", row.id)), row.variants.size()]
		else:
			text = "H%d  %s%s" % [int(row.get("hour", 0)), str(row.get("title", id)), "" if row.get("acknowledged", false) else "（待阅）"]
		var index := _list.add_item(text)
		_list.set_item_metadata(index, id)
		_list.set_item_tooltip(index, text)
		if id == str(_selected[_tab]): _list.select(index)
	_listing_title.text = "本局已发现家族 · %d" % _memes.size() if _tab == "memes" else "本局已经出现事件 · %d" % _events.size()
	_empty.text = "本局尚未发现模因。" if _tab == "memes" else "本局尚未出现事件。"
	_empty.visible = rows.is_empty()
	_meme_tab.button_pressed = _tab == "memes"
	_event_tab.button_pressed = _tab == "events"
	var usable := _focused and not _closing and not _blocked and _mix == 1.0
	for button in [_meme_tab, _event_tab, _close_button]: button.disabled = not usable
	_list.mouse_filter = Control.MOUSE_FILTER_STOP if usable else Control.MOUSE_FILTER_IGNORE
	_view_button.visible = _tab == "events"
	_view_button.disabled = not usable or _event_by_id(str(_selected.events)).is_empty()
	_show_details()


func _show_details() -> void:
	_title.text = "尚无档案"
	_details.text = "只记录这一局实际出现的家族、版本和事件。"
	if _tab == "events":
		var event := _event_by_id(str(_selected.events))
		if event.is_empty(): return
		_title.text = str(event.get("title", event.instance_id))
		_details.text = "%s · H%d · %s\n%s\n\n新闻\n%s\n\n作用摘录\n%s\n\n实际作用\n%s\n\n67：%s" % [str(event.instance_id), int(event.get("hour", 0)), str(event.get("origin", "")), "已收阅" if event.get("acknowledged", false) else "已出现，尚未收阅；档案查看不会确认", str(event.get("narrative", "")), str(event.get("impact_text", "")), str(event.get("effect_text", "")), str(event.get("mentor_comment", ""))]
		return
	for row in _memes:
		if str(row.id) != str(_selected.memes): continue
		_title.text = str(row.family.get("anchor", row.id))
		var lines := PackedStringArray(["家族 " + str(row.id), "家族归属 " + str(row.family.get("owner", "记录未提供"))])
		var derived: Array = row.family.get("derived_from", []) if row.family.get("derived_from", []) is Array else []
		if not derived.is_empty(): lines.append("分家来源 " + ", ".join(derived))
		for variant in row.variants:
			lines.append("\n版本 %s · 创作者 %s\n%s\n作者归属 %s · 受控 %s" % [str(variant.id), str(variant.get("creator", "记录未提供")), str(variant.get("text", "")), "是" if variant.get("owned", false) else "否", "是" if variant.get("controlled", false) else "否"])
			var parents: Array = variant.get("parent_ids", []) if variant.get("parent_ids", []) is Array else []
			if not parents.is_empty(): lines.append("父版本 " + ", ".join(parents))
			var origins: Array = variant.get("origin_ids", []) if variant.get("origin_ids", []) is Array else []
			if not origins.is_empty(): lines.append("来源版本 " + ", ".join(origins))

		_details.text = "\n".join(lines)
		return


func _layout() -> void:
	var available := Vector2(maxf(300.0, _view.size.x - 70.0), maxf(240.0, _view.size.y - 72.0))
	var texture := _textures.get("open") as Texture2D
	var ratio := texture.get_size().x / texture.get_size().y if texture != null else 1.654
	# Whole pixels keep native offsets stable and printed text sharp.
	var width := floorf(minf(1040.0, minf(available.x, available.y * ratio)))
	var height := floorf(width / ratio)
	_target = Rect2(_view.position + (_view.size - Vector2(width, height)) * 0.5, Vector2(width, height))
	if not _built: return
	_ui.size = size
	_shade.size = size
	_pages.position = _target.position - global_position
	_pages.size = _target.size
	var w := width
	var h := height
	_meme_tab.position = Vector2(w*.09, h*.055)
	_meme_tab.size = Vector2(w*.19, maxf(34.0, h*.065))
	_event_tab.position = Vector2(w*.79, h*.055)
	_event_tab.size = Vector2(w*.15, maxf(34.0, h*.065))
	_close_button.position = Vector2(w - 114, -30)
	_close_button.size = Vector2(110, 28)
	_listing_title.position = Vector2(w*.075, h*.17)
	_listing_title.size = Vector2(w*.405, 32)
	_list.position = Vector2(w*.073, h*.24)
	_list.size = Vector2(w*.405, h*.64)
	_empty.position = _list.position + Vector2(6, 12)
	_empty.size = _list.size - Vector2(12, 24)
	_title.position = Vector2(w*.548, h*.16)
	_title.size = Vector2(w*.38, h*.11)
	_details.position = Vector2(w*.548, h*.29)
	_details.size = Vector2(w*.38, h*.48)
	_notice.position = Vector2(w*.548, h*.85)
	_notice.size = Vector2(w*.38, h*.075)
	_view_button.position = Vector2(w*.548, h*.78)
	_view_button.size = Vector2(w*.24, 32)
	_flip_sheet.position = Vector2(w*.53, h*.14)
	_flip_sheet.size = Vector2(w*.422, h*.78)
	_flip_sheet.pivot_offset = Vector2(0, _flip_sheet.size.y*.5)


func _animate_focus(target: float) -> void:
	if _focus_tween != null and _focus_tween.is_valid(): _focus_tween.kill()
	_focus_tween = create_tween()
	_focus_tween.tween_method(_apply_pose, _mix, target, maxf(0.01, focus_duration)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.tween_callback(_finish_focus.bind(target))


func _apply_pose(value: float) -> void:
	_mix = value
	if is_instance_valid(_folder) and not _saved_pose.is_empty():
		var parent := _folder.get_parent() as CanvasItem
		var target_position := parent.get_global_transform_with_canvas().affine_inverse() * _target.position if parent != null else _target.position
		_folder.position = Vector2(_saved_pose.position).lerp(target_position, value)
		_folder.size = Vector2(_saved_pose.size).lerp(_target.size, value)
		_folder.rotation = lerpf(float(_saved_pose.rotation), 0.0, value)
		if value == 1.0:
			_folder.position = target_position
			_folder.size = _target.size
			_folder.rotation = 0.0
	if _built:
		_pages.modulate.a = value
		_shade.color.a = 0.38 * value


func _finish_focus(target: float) -> void:
	_mix = target
	if target == 0.0:
		_restore_folder()
		_focused = false
		_closing = false
		_refresh()
		focus_changed.emit(false)
	else:
		_refresh()


func _restore_folder() -> void:
	if is_instance_valid(_folder) and not _saved_pose.is_empty():
		for key in _saved_pose: _folder.set(key, _saved_pose[key])
	_saved_pose = {}


func _flip() -> void:
	if not _built or not _focused or _mix != 1.0: return
	_flips += 1
	if _flip_tween != null and _flip_tween.is_valid(): _flip_tween.kill()
	_flip_sheet.scale.x = 0.04
	_flip_sheet.modulate.a = 0.7
	_flip_tween = create_tween().set_parallel(true)
	_flip_tween.tween_property(_flip_sheet, "scale:x", 1.0, maxf(0.02, flip_duration)).set_trans(Tween.TRANS_SINE)
	_flip_tween.tween_property(_flip_sheet, "modulate:a", 0.0, maxf(0.02, flip_duration))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and handle_key(event): get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_restore_folder()
