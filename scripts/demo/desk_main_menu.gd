class_name DeskMainMenu
extends Control

signal start_requested
signal load_requested
signal codex_requested
signal quit_requested
signal settings_changed(settings: Dictionary)

const TEMPLATE = preload("res://scenes/demo/v11/desk_main_menu_ui.tscn")
const PaperStyle = preload("res://scripts/demo/desk_paper_style.gd")
const LABELS := {
	"zh_CN": ["模因工作室", "印刷不保证理解。", "开始", "读取", "模因图鉴", "设置", "退出", "语言", "音乐", "音效", "返回", "语言切换适用于界面与已有译文。"],
	"en": ["Memeplex Studio", "Printing does not guarantee understanding.", "Start", "Load", "Codex", "Settings", "Quit", "Language", "Music", "Effects", "Back", "Language applies to the interface and existing translations."]
}

var settings_path := "user://meme_interface.cfg"
var _settings := {"language": "zh_CN", "music": 1.0, "effects": 1.0}
var _music_bus := "BGM"
var _effect_buses := PackedStringArray(["SFX", "BGS", "MFX"])
var _ui: Control
var _load_available := false
var _existing_background := false
var _last_error := OK

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme == null: theme = load("res://assets/themes/demo_theme.tres")
	_ui = TEMPLATE.instantiate()
	add_child(_ui)
	_ui.get_node("MenuPanel/Content/Start").pressed.connect(func(): start_requested.emit())
	_ui.get_node("MenuPanel/Content/Load").pressed.connect(func():
		if _load_available: load_requested.emit())
	_ui.get_node("MenuPanel/Content/Codex").pressed.connect(func(): codex_requested.emit())
	_ui.get_node("MenuPanel/Content/Quit").pressed.connect(func(): quit_requested.emit())
	_ui.get_node("MenuPanel/Content/Settings").pressed.connect(open_settings)
	_ui.get_node("SettingsPanel/Content/Back").pressed.connect(close_settings)
	_ui.get_node("SettingsPanel/Content/Language").item_selected.connect(func(index: int): change_language("zh_CN" if index == 0 else "en"))
	for entry: Array in [["Music", "music"], ["Effects", "effects"]]:
		var slider: HSlider = _ui.get_node("SettingsPanel/Content/" + entry[0])
		slider.value_changed.connect(func(value: float): set_volume(entry[1], value))
	PaperStyle.apply_buttons(_ui.get_node("MenuPanel"))
	PaperStyle.apply_buttons(_ui.get_node("SettingsPanel"))
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

func load_settings() -> Error:
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		_last_error = error
		return error
	if error == OK:
		var locale := str(config.get_value("interface", "language", "zh_CN"))
		if locale in ["zh_CN", "en"]: _settings.language = locale
		for kind: String in ["music", "effects"]:
			var value: Variant = config.get_value("audio", kind, 1.0)
			if (value is float or value is int) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 1: _settings[kind] = float(value)
	TranslationServer.set_locale(_settings.language)
	_apply_audio()
	_refresh_labels()
	return error

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("interface", "language", _settings.language)
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
	var words: Array = LABELS[_settings.language]
	var keys := ["Title", "Subtitle", "Start", "Load", "Codex", "Settings", "Quit"]
	for index in keys.size(): _ui.get_node("MenuPanel/Content/" + keys[index]).text = words[index]
	for pair: Array in [["Title", 5], ["LanguageLabel", 7], ["MusicLabel", 8], ["EffectsLabel", 9], ["Back", 10], ["Notice", 11]]:
		_ui.get_node("SettingsPanel/Content/" + pair[0]).text = words[pair[1]]
	if _last_error != OK: _ui.get_node("SettingsPanel/Content/Notice").text = error_string(_last_error)
	_ui.get_node("SettingsPanel/Content/Language").select(0 if _settings.language == "zh_CN" else 1)
	for pair: Array in [["Music", "music"], ["Effects", "effects"]]:
		_ui.get_node("SettingsPanel/Content/" + pair[0]).set_value_no_signal(_settings[pair[1]])
		_ui.get_node("SettingsPanel/Content/" + pair[0] + "Value").text = "%d%%" % roundi(float(_settings[pair[1]]) * 100)
	set_load_available(_load_available)

func _layout() -> void:
	if not is_instance_valid(_ui): return
	_ui.get_node("Background").visible = not _existing_background
	for name: String in ["MenuPanel", "SettingsPanel"]:
		var panel: Control = _ui.get_node(name)
		panel.size = Vector2(minf(520, size.x - 40), minf(550, size.y - 32))
		panel.position = (size - panel.size) * 0.5
		var content: Control = panel.get_node("Content")
		content.position = Vector2(48, 40)
		content.size = panel.size - Vector2(96, 80)

func inspection() -> Dictionary:
	var buses := {}
	for name: String in PackedStringArray([_music_bus]) + _effect_buses:
		var index := AudioServer.get_bus_index(name)
		buses[name] = {"linear": AudioServer.get_bus_volume_linear(index), "muted": AudioServer.is_bus_mute(index)} if index >= 0 else {}
	return {"visible": is_visible_in_tree(), "screen": "settings" if is_instance_valid(_ui) and _ui.get_node("SettingsPanel").visible else "menu", "settings": _settings.duplicate(true), "settings_path": settings_path, "load_available": _load_available, "audio_buses": buses, "last_error": _last_error, "translation_locale": TranslationServer.get_locale(), "scope": "Own interface labels and existing project translations"}
