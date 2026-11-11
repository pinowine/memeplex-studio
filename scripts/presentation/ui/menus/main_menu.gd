class_name DeskMainMenu
extends Control

signal start_requested
signal new_game_requested
signal load_requested
signal quit_requested
signal settings_changed(settings: Dictionary)
signal settings_closed

const TEMPLATE = preload("res://scenes/ui/menus/main_menu.tscn")
const ReceiptUI = preload("res://scripts/presentation/studio/paper/desk_receipt_ui.gd")
const KeyBindings = preload("res://scripts/presentation/ui/menus/key_bindings.gd")
const LABELS := ["LOC_MEMEPLEX_STUDIO_3D1D137F", "LOC_MAIN_NEW_GAME", "LOC_MAIN_LOAD_GAME", "LOC_SETTINGS_DF3D58C7", "LOC_QUIT_498E1D59", "LOC_LANGUAGE_9F6FEE1A", "LOC_MUSIC_DB951421", "LOC_EFFECTS_5E9D80D0", "LOC_BACK_572CF45B", "LOC_SWITCH_THE_INTERFACE_AND_AUTHORED_CONTENT_BETWEEN_3AF98B71"]

var settings_path := "user://meme_interface.cfg"
var _settings := {"language": "en", "music": 1.0, "effects": 1.0, "guide_enabled": true, "typewriter_enabled": true, "key_bindings": {}}
var _music_bus := "BGM"
var _effect_buses := PackedStringArray(["SFX", "BGS", "MFX"])
var _ui: Control
var _load_available := false
var _continue_available := false
var _existing_background := false
var _last_error := OK
var _settings_in_game := false
var _binding_capture := ""
var _binding_buttons: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ReceiptUI.create_theme()
	_ui = TEMPLATE.instantiate()
	add_child(_ui)
	_ui.get_node("MenuPanel/Content/Start").pressed.connect(func(): start_requested.emit())
	_ui.get_node("MenuPanel/Content/NewGame").pressed.connect(func(): new_game_requested.emit())
	_ui.get_node("MenuPanel/Content/Load").pressed.connect(func():
		if _load_available: load_requested.emit())
	_ui.get_node("MenuPanel/Content/Quit").pressed.connect(func(): quit_requested.emit())
	_ui.get_node("MenuPanel/Content/Settings").pressed.connect(open_settings)
	_ui.get_node("SettingsPanel/Content/Back").pressed.connect(close_settings)
	_ui.get_node("SettingsPanel/Content/LanguageRow/Language").item_selected.connect(func(index: int): change_language("zh_CN" if index == 0 else "en"))
	_ui.get_node("SettingsPanel/Content/GuideEnabled").toggled.connect(set_guide_enabled)
	_ui.get_node("SettingsPanel/Content/TypewriterEnabled").toggled.connect(set_typewriter_enabled)
	_ui.get_node("SettingsPanel/Content/KeyBindings").pressed.connect(open_key_bindings)
	_ui.get_node("KeysPanel/Content/Back").pressed.connect(close_key_bindings)
	_ui.get_node("KeysPanel/Content/Reset").pressed.connect(reset_key_bindings)
	_install_key_bindings()
	for entry: Array in [["Music", "music"], ["Effects", "effects"]]:
		var slider: HSlider = _ui.get_node("SettingsPanel/Content/" + entry[0] + "Row/" + entry[0])
		slider.value_changed.connect(func(value: float): set_volume(entry[1], value))
	_style_desktop_menu()
	ReceiptUI.primary(_ui.get_node("SettingsPanel/Content/Back"))
	ReceiptUI.primary(_ui.get_node("KeysPanel/Content/Back"))
	for name: String in ["MenuPanel", "SettingsPanel", "KeysPanel"]:
		_ui.get_node(name + "/Content").minimum_size_changed.connect(_layout)
	resized.connect(_layout)
	load_settings()
	_layout()

func configure(options: Dictionary = {}) -> void:
	settings_path = str(options.get("settings_path", settings_path))
	_music_bus = str(options.get("music_bus", _music_bus))
	_effect_buses = PackedStringArray(options.get("effect_buses", _effect_buses))
	_existing_background = bool(options.get("existing_background", false))
	if is_instance_valid(_ui):
		load_settings()
		_layout()

func show_menu() -> void:
	_settings_in_game = false
	show()
	close_settings()
	report_load_error("")
	_ui.get_node("MenuPanel/Content/Start").grab_focus()

func hide_menu() -> void:
	hide()

func set_load_available(value: bool) -> void:
	_load_available = value
	if is_instance_valid(_ui): _ui.get_node("MenuPanel/Content/Load").disabled = not value

func set_continue_available(value: bool) -> void:
	_continue_available = value
	_refresh_labels()

func report_load_error(message: String) -> void:
	var notice: Label = _ui.get_node("MenuPanel/Content/LoadError")
	notice.text = message
	notice.visible = not message.is_empty()
	_layout()
	_layout.call_deferred()

func _style_desktop_menu() -> void:
	# Ivory lettering keeps the title and actions legible on the wood.
	var title: Label = _ui.get_node("MenuPanel/Content/Title")
	title.add_theme_font_override("font", preload("res://assets/image/fonts/print_heading_font.tres"))
	for label: Label in [title, _ui.get_node("Version"), _ui.get_node("MenuPanel/Content/LoadError")]:
		label.add_theme_color_override("font_color", ReceiptUI.Style.PAPER)
		label.add_theme_color_override("font_shadow_color", ReceiptUI.Style.SECTION_BROWN)
		label.add_theme_constant_override("shadow_offset_y", 2)
	_ui.get_node("Version").text = "v" + str(ProjectSettings.get_setting("application/config/version"))
	for id: String in ["Start", "NewGame", "Load", "Settings", "Quit"]:
		var button: Button = _ui.get_node("MenuPanel/Content/" + id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 24)
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			var box := StyleBoxFlat.new()
			box.content_margin_left = 24
			box.content_margin_right = 24
			box.content_margin_top = 8
			box.content_margin_bottom = 8
			box.bg_color = ReceiptUI.Style.PAPER if id == "Start" or state in ["hover", "pressed"] else Color.TRANSPARENT
			if state == "pressed": box.bg_color = ReceiptUI.Style.EDGE
			if state == "focus":
				box.bg_color = Color.TRANSPARENT
				box.border_color = ReceiptUI.Style.PAPER
				box.border_width_bottom = 2
			button.add_theme_stylebox_override(state, box)
		for state: String in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(state, ReceiptUI.Style.INK if id == "Start" or state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"] else ReceiptUI.Style.PAPER)
		button.add_theme_color_override("font_disabled_color", ReceiptUI.Style.EDGE)

func open_settings() -> void:
	_ui.get_node("MenuPanel").hide()
	_ui.get_node("KeysPanel").hide()
	_ui.get_node("SettingsPanel").show()
	_ui.get_node("SettingsPanel/Content/LanguageRow/Language").grab_focus()
	_layout()

func show_settings() -> void:
	_settings_in_game = true
	show()
	move_to_front()
	open_settings()

func close_settings() -> void:
	if not is_instance_valid(_ui): return
	_cancel_binding_capture()
	_ui.get_node("KeysPanel").hide()
	_ui.get_node("SettingsPanel").hide()
	if _settings_in_game:
		_settings_in_game = false
		hide()
		settings_closed.emit()
	else:
		_ui.get_node("MenuPanel").show()
		_ui.get_node("MenuPanel/Content/Settings").grab_focus()
	_layout()

func back() -> bool:
	if not _binding_capture.is_empty():
		_cancel_binding_capture()
	elif _ui.get_node("KeysPanel").visible:
		close_key_bindings()
	elif _ui.get_node("SettingsPanel").visible:
		close_settings()
	else:
		return false
	return true

func open_key_bindings() -> void:
	_ui.get_node("SettingsPanel").hide()
	_ui.get_node("KeysPanel").show()
	_binding_buttons[KeyBindings.ACTION_IDS[0]].grab_focus()
	_layout()

func close_key_bindings() -> void:
	_cancel_binding_capture()
	_ui.get_node("KeysPanel").hide()
	_ui.get_node("SettingsPanel").show()
	_ui.get_node("SettingsPanel/Content/KeyBindings").grab_focus()
	_layout()

func _install_key_bindings() -> void:
	var rows: VBoxContainer = _ui.get_node("KeysPanel/Content/Rows")
	for action: String in KeyBindings.ACTION_IDS:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 44
		row.add_theme_constant_override("separation", 12)
		rows.add_child(row)
		var label := Label.new()
		label.text = KeyBindings.LABELS[action]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size.x = 164
		button.pressed.connect(func(): _begin_binding_capture(action))
		row.add_child(button)
		_binding_buttons[action] = button

func _begin_binding_capture(action: String) -> void:
	_binding_capture = action
	_refresh_binding_labels()

func _cancel_binding_capture() -> void:
	_binding_capture = ""
	_refresh_binding_labels()

func reset_key_bindings() -> void:
	_cancel_binding_capture()
	KeyBindings.reset()
	_settings.key_bindings = KeyBindings.bindings()
	save_settings()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey: return
	var key: Key = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key == KEY_ESCAPE and event.pressed and not event.echo and back():
		get_viewport().set_input_as_handled()
		return
	if _binding_capture.is_empty(): return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo: return
	if KeyBindings.assign(_binding_capture, event) != OK: return
	_binding_capture = ""
	_settings.key_bindings = KeyBindings.bindings()
	save_settings()

func _refresh_binding_labels() -> void:
	for action: String in _binding_buttons:
		_binding_buttons[action].text = "LOC_KEY_PRESS_KEY" if action == _binding_capture else KeyBindings.display_name(action)

func change_language(locale: String) -> Error:
	if locale not in ["zh_CN", "en"]: return ERR_INVALID_PARAMETER
	_settings.language = locale
	TranslationServer.set_locale(locale)
	_refresh_labels()
	return save_settings()

func set_volume(kind: String, value: float, persist: bool = true) -> Error:
	if kind not in ["music", "effects"] or not is_finite(value) or value < 0 or value > 1: return ERR_INVALID_PARAMETER
	_settings[kind] = value
	_apply_audio()
	_refresh_labels()
	return save_settings() if persist else OK

func guide_enabled() -> bool:
	return bool(_settings.guide_enabled)

func typewriter_enabled() -> bool:
	return bool(_settings.typewriter_enabled)

func set_typewriter_enabled(enabled: bool) -> Error:
	_settings.typewriter_enabled = enabled
	return save_settings()

func set_guide_enabled(enabled: bool) -> Error:
	var previous := guide_enabled()
	_settings.guide_enabled = enabled
	var error := save_settings()
	if error != OK:
		_settings.guide_enabled = previous
		_refresh_labels()
	return error

func load_settings() -> Error:
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		_last_error = error
		_refresh_labels()
		return error
	var guide: Variant = config.get_value("interface", "guide_enabled", true)
	_settings.guide_enabled = guide if guide is bool else true
	_settings.typewriter_enabled = bool(config.get_value("interface", "typewriter_enabled", true))
	KeyBindings.apply(config.get_value("interface", "key_bindings", {}))
	_settings.key_bindings = KeyBindings.bindings()
	_last_error = OK if guide is bool else ERR_INVALID_DATA
	if error == OK:
		var locale := str(config.get_value("interface", "language", "en"))
		if locale in ["zh_CN", "en"]: _settings.language = locale
		for kind: String in ["music", "effects"]:
			var value: Variant = config.get_value("audio", kind, 1.0)
			if (value is float or value is int) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 1: _settings[kind] = float(value)
	TranslationServer.set_locale(_settings.language)
	_apply_audio()
	_refresh_labels()
	return error if _last_error == OK else _last_error

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("interface", "language", _settings.language)
	config.set_value("interface", "guide_enabled", _settings.guide_enabled)
	config.set_value("interface", "typewriter_enabled", _settings.typewriter_enabled)
	config.set_value("interface", "key_bindings", _settings.key_bindings)
	for kind: String in ["music", "effects"]: config.set_value("audio", kind, _settings[kind])
	var absolute := ProjectSettings.globalize_path(settings_path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error == OK: error = config.save(absolute + ".tmp")
	if error == OK: error = DirAccess.rename_absolute(absolute + ".tmp", absolute)
	_last_error = error
	if error == OK: settings_changed.emit(_settings.duplicate(true))
	_refresh_labels()
	return error

func _ensure_bus(name: String) -> int:
	var index := AudioServer.get_bus_index(name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, name)
	return index

func _apply_audio() -> void:
	for name: String in PackedStringArray([_music_bus]) + _effect_buses:
		var value := float(_settings.music if name == _music_bus else _settings.effects)
		var index := _ensure_bus(name)
		AudioServer.set_bus_volume_linear(index, value)
		AudioServer.set_bus_mute(index, value == 0)

func _refresh_labels() -> void:
	if not is_instance_valid(_ui): return
	var words: Array = LABELS
	var keys := ["Title", "Start", "Load", "Settings", "Quit"]
	for index in keys.size(): _ui.get_node("MenuPanel/Content/" + keys[index]).text = words[index]
	_ui.get_node("MenuPanel/Content/Start").text = "LOC_CONTINUE_7C969119" if _continue_available else "LOC_MAIN_NEW_GAME"
	_ui.get_node("MenuPanel/Content/NewGame").visible = _continue_available
	for pair: Array in [["Title", 3], ["LanguageRow/LanguageLabel", 5], ["MusicRow/MusicLabel", 6], ["EffectsRow/EffectsLabel", 7], ["Back", 8]]:
		_ui.get_node("SettingsPanel/Content/" + pair[0]).text = words[pair[1]]
	var notice: Label = _ui.get_node("SettingsPanel/Content/Notice")
	notice.visible = _last_error != OK
	if notice.visible: notice.text = error_string(_last_error)
	_ui.get_node("SettingsPanel/Content/LanguageRow/Language").select(0 if _settings.language == "zh_CN" else 1)
	_ui.get_node("SettingsPanel/Content/GuideEnabled").set_pressed_no_signal(_settings.guide_enabled)
	_ui.get_node("SettingsPanel/Content/TypewriterEnabled").set_pressed_no_signal(_settings.typewriter_enabled)
	for pair: Array in [["Music", "music"], ["Effects", "effects"]]:
		_ui.get_node("SettingsPanel/Content/" + pair[0] + "Row/" + pair[0]).set_value_no_signal(_settings[pair[1]])
		_ui.get_node("SettingsPanel/Content/" + pair[0] + "Row/" + pair[0] + "Value").text = "%d%%" % roundi(float(_settings[pair[1]]) * 100)
	_refresh_binding_labels()
	set_load_available(_load_available)
	_layout()
	_layout.call_deferred()

func _layout() -> void:
	if not is_instance_valid(_ui): return
	_ui.get_node("Background").visible = not _existing_background
	_ui.get_node("Shade").visible = not _ui.get_node("MenuPanel").visible
	_ui.get_node("Version").visible = _ui.get_node("MenuPanel").visible
	var menu: Control = _ui.get_node("MenuPanel")
	var content: Control = menu.get_node("Content")
	var scale_factor := minf(size.x / 1600.0, size.y / 900.0)
	menu.scale = Vector2.ONE * scale_factor
	content.position = Vector2.ZERO
	content.size = content.get_combined_minimum_size()
	menu.size = content.size
	menu.position = Vector2(size.x * .30, minf(size.y * .30, size.y - content.size.y * scale_factor - 32.0 * scale_factor))
	for name: String in ["SettingsPanel", "KeysPanel"]:
		var panel: Control = _ui.get_node(name)
		ReceiptUI.layout_menu(panel, panel.get_node("Content"), size)

func inspection() -> Dictionary:
	var buses := {}
	for name: String in PackedStringArray([_music_bus]) + _effect_buses:
		var index := AudioServer.get_bus_index(name)
		buses[name] = {"linear": AudioServer.get_bus_volume_linear(index), "muted": AudioServer.is_bus_mute(index)} if index >= 0 else {}
	var screen := "keys" if is_instance_valid(_ui) and _ui.get_node("KeysPanel").visible else ("settings" if is_instance_valid(_ui) and _ui.get_node("SettingsPanel").visible else "menu")
	return {"visible": is_visible_in_tree(), "screen": screen, "settings": _settings.duplicate(true), "settings_path": settings_path, "load_available": _load_available, "audio_buses": buses, "last_error": _last_error, "translation_locale": TranslationServer.get_locale(), "binding_capture":_binding_capture, "scope": "Own interface labels and existing project translations"}
