class_name DeskMainMenu
extends Control

signal start_requested
signal load_requested
signal quit_requested
signal settings_changed(settings: Dictionary)

const TEMPLATE = preload("res://scenes/ui/menus/main_menu.tscn")
const ReceiptUI = preload("res://scripts/presentation/studio/paper/desk_receipt_ui.gd")
const LABELS := ["LOC_MEMEPLEX_STUDIO_3D1D137F", "LOC_START_D2BB025A", "LOC_LOAD_534CB3FA", "LOC_SETTINGS_DF3D58C7", "LOC_QUIT_498E1D59", "LOC_LANGUAGE_9F6FEE1A", "LOC_MUSIC_DB951421", "LOC_EFFECTS_5E9D80D0", "LOC_BACK_572CF45B", "LOC_SWITCH_THE_INTERFACE_AND_AUTHORED_CONTENT_BETWEEN_3AF98B71"]

var settings_path := "user://meme_interface.cfg"
var _settings := {"language": "zh_CN", "music": 1.0, "effects": 1.0, "guide_enabled": true}
var _music_bus := "BGM"
var _effect_buses := PackedStringArray(["SFX", "BGS", "MFX"])
var _ui: Control
var _load_available := false
var _existing_background := false
var _last_error := OK

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = ReceiptUI.create_theme()
	_ui = TEMPLATE.instantiate()
	add_child(_ui)
	_ui.get_node("MenuPanel/Content/Start").pressed.connect(func(): start_requested.emit())
	_ui.get_node("MenuPanel/Content/Load").pressed.connect(func():
		if _load_available: load_requested.emit())
	_ui.get_node("MenuPanel/Content/Quit").pressed.connect(func(): quit_requested.emit())
	_ui.get_node("MenuPanel/Content/Settings").pressed.connect(open_settings)
	_ui.get_node("SettingsPanel/Content/Back").pressed.connect(close_settings)
	_ui.get_node("SettingsPanel/Content/Language").item_selected.connect(func(index: int): change_language("zh_CN" if index == 0 else "en"))
	_ui.get_node("SettingsPanel/Content/GuideEnabled").toggled.connect(set_guide_enabled)
	for entry: Array in [["Music", "music"], ["Effects", "effects"]]:
		var slider: HSlider = _ui.get_node("SettingsPanel/Content/" + entry[0])
		slider.value_changed.connect(func(value: float): set_volume(entry[1], value))
	ReceiptUI.primary(_ui.get_node("MenuPanel/Content/Start"))
	ReceiptUI.primary(_ui.get_node("SettingsPanel/Content/Back"))
	for name: String in ["MenuPanel", "SettingsPanel"]:
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
	show()
	close_settings()

func hide_menu() -> void:
	hide()

func set_load_available(value: bool) -> void:
	_load_available = value
	if is_instance_valid(_ui): _ui.get_node("MenuPanel/Content/Load").disabled = not value

func open_settings() -> void:
	_ui.get_node("MenuPanel").hide()
	_ui.get_node("SettingsPanel").show()
	_ui.get_node("SettingsPanel/Content/Language").grab_focus()

func close_settings() -> void:
	if not is_instance_valid(_ui): return
	_ui.get_node("SettingsPanel").hide()
	_ui.get_node("MenuPanel").show()

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
	_last_error = OK if guide is bool else ERR_INVALID_DATA
	if error == OK:
		var locale := str(config.get_value("interface", "language", "zh_CN"))
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
	for pair: Array in [["Title", 3], ["LanguageLabel", 5], ["MusicHeading/MusicLabel", 6], ["EffectsHeading/EffectsLabel", 7], ["Back", 8]]:
		_ui.get_node("SettingsPanel/Content/" + pair[0]).text = words[pair[1]]
	var notice: Label = _ui.get_node("SettingsPanel/Content/Notice")
	notice.visible = _last_error != OK
	if notice.visible: notice.text = error_string(_last_error)
	_ui.get_node("SettingsPanel/Content/Language").select(0 if _settings.language == "zh_CN" else 1)
	_ui.get_node("SettingsPanel/Content/GuideEnabled").set_pressed_no_signal(_settings.guide_enabled)
	for pair: Array in [["Music", "music"], ["Effects", "effects"]]:
		_ui.get_node("SettingsPanel/Content/" + pair[0]).set_value_no_signal(_settings[pair[1]])
		_ui.get_node("SettingsPanel/Content/" + pair[0] + "Heading/" + pair[0] + "Value").text = "%d%%" % roundi(float(_settings[pair[1]]) * 100)
	set_load_available(_load_available)
	_layout()

func _layout() -> void:
	if not is_instance_valid(_ui): return
	_ui.get_node("Background").visible = not _existing_background
	for name: String in ["MenuPanel", "SettingsPanel"]:
		var panel: Control = _ui.get_node(name)
		ReceiptUI.layout_menu(panel, panel.get_node("Content"), size)

func inspection() -> Dictionary:
	var buses := {}
	for name: String in PackedStringArray([_music_bus]) + _effect_buses:
		var index := AudioServer.get_bus_index(name)
		buses[name] = {"linear": AudioServer.get_bus_volume_linear(index), "muted": AudioServer.is_bus_mute(index)} if index >= 0 else {}
	return {"visible": is_visible_in_tree(), "screen": "settings" if is_instance_valid(_ui) and _ui.get_node("SettingsPanel").visible else "menu", "settings": _settings.duplicate(true), "settings_path": settings_path, "load_available": _load_available, "audio_buses": buses, "last_error": _last_error, "translation_locale": TranslationServer.get_locale(), "scope": "Own interface labels and existing project translations"}
