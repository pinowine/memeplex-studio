class_name DeskLocalization
extends RefCounted

const DEFAULT_TABLES := ["res://localization/messages.json", "res://localization/tutorial.json"]
const EDIT_META := &"desk_localization_edit"
const EDIT_CONNECTED_META := &"desk_localization_edit_connected"

static var _initialized := false
static var _translation: Translation
static var _chinese_translation: Translation
static var _records: Dictionary = {}
static var _record_paths: Dictionary = {}
static var _messages: Dictionary = {}
static var _chinese_messages: Dictionary = {}
static var _aliases: Dictionary = {}
static var _dynamic_messages: Dictionary = {}
static var _dynamic_chinese: Dictionary = {}
static var _dynamic_specs: Dictionary = {}
static var _missing: Dictionary = {}
static var _table_paths: Array[String] = []
static var _load_errors: Array[String] = []
static var _last_reload_errors: Array[String] = []
static var _load_error: Error = OK

static func ensure_loaded(paths: Array = DEFAULT_TABLES) -> Error:
	if _initialized: return _load_error
	var error := reload_tables(paths)
	if error != OK:
		_initialized = true
		_load_error = error
		_load_errors.assign(_last_reload_errors)
	return error

static func reload_tables(paths: Array = DEFAULT_TABLES) -> Error:
	var combined: Dictionary = {}
	var record_paths: Dictionary = {}
	var loaded_paths: Array[String] = []
	var errors: Array[String] = []
	var result: Error = OK
	if paths.is_empty():
		errors.append("At least one translation table is required.")
		result = ERR_INVALID_PARAMETER
	for value: Variant in paths:
		if not value is String:
			errors.append("Translation table path must be a string.")
			result = ERR_INVALID_PARAMETER
			continue
		var path := str(value)
		loaded_paths.append(path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("Cannot open translation table: " + path)
			result = FileAccess.get_open_error()
			continue
		var parser := JSON.new()
		var error := parser.parse(file.get_as_text())
		file.close()
		if error != OK or not parser.data is Dictionary:
			errors.append("Translation table must contain a JSON object: " + path)
			result = ERR_PARSE_ERROR
			continue
		var table: Dictionary = parser.data
		var flat := not table.is_empty() and table.values()[0] is String and path not in DEFAULT_TABLES
		var invalid := validate_messages(table) if flat else validate_keyed_messages(table)
		if not invalid.is_empty():
			for message: String in invalid: errors.append(path + ": " + message)
			result = ERR_INVALID_DATA
			continue
		for key: String in table:
			var entry: Dictionary = {"source":key, "zh_CN":key, "en":table[key]} if flat else table[key].duplicate(true)
			if combined.has(key) and combined[key] != entry:
				errors.append("Conflicting translation key: " + key)
				result = ERR_INVALID_DATA
			else:
				combined[key] = entry
				record_paths[key] = path
	var aliases: Dictionary = {}
	for key: String in combined:
		var canonical := str(combined[key].source)
		if _records.has(key) and str(_records[key].source) != canonical:
			errors.append("Canonical source is immutable for translation key: " + key)
			result = ERR_INVALID_DATA
		if combined.has(canonical) and canonical != key:
			errors.append("Canonical source conflicts with a translation key: " + key)
			result = ERR_INVALID_DATA
		if aliases.has(canonical) and combined[aliases[canonical]] != combined[key]:
			errors.append("Conflicting translations for canonical source: " + canonical)
			result = ERR_INVALID_DATA
		aliases[canonical] = key
	_last_reload_errors = errors
	if result != OK:
		for message: String in errors: push_error(message)
		return result
	var old_english := _translation
	var old_chinese := _chinese_translation
	_records = combined
	_record_paths = record_paths
	_aliases = aliases
	_messages = {}
	_chinese_messages = {}
	_translation = Translation.new()
	_translation.locale = "en"
	_chinese_translation = Translation.new()
	_chinese_translation.locale = "zh_CN"
	for key: String in _records:
		var entry: Dictionary = _records[key]
		for alias: String in [key, str(entry.source)]:
			_messages[alias] = entry.en
			_chinese_messages[alias] = entry.zh_CN
			_translation.add_message(StringName(alias), StringName(entry.en))
			_chinese_translation.add_message(StringName(alias), StringName(entry.zh_CN))
	_table_paths = loaded_paths
	_load_errors.clear()
	_load_error = OK
	_missing.clear()
	_initialized = true
	_dynamic_messages.clear()
	_dynamic_chinese.clear()
	for canonical: String in _dynamic_specs:
		_rebuild_dynamic(canonical, _dynamic_specs[canonical])
	# Presenters observe only a validated table with both locales available.
	if old_english != null: TranslationServer.remove_translation(old_english)
	if old_chinese != null: TranslationServer.remove_translation(old_chinese)
	TranslationServer.add_translation(_translation)
	TranslationServer.add_translation(_chinese_translation)
	return OK

static func text_source(key: String) -> Dictionary:
	ensure_loaded()
	var identity := str(_aliases.get(key, key))
	if not _records.has(identity): return {}
	return {"key":identity, "path":str(_record_paths[identity])}

static func source(key: String) -> String:
	ensure_loaded()
	return str(_records[key].source) if _records.has(key) else key

static func source_value(value: Variant) -> Variant:
	if value is String: return source(value)
	if value is StringName: return StringName(source(str(value)))
	if value is PackedStringArray:
		var strings := PackedStringArray()
		for item: String in value: strings.append(source(item))
		return strings
	if value is Array:
		var items: Array = value.duplicate()
		for index in items.size(): items[index] = source_value(items[index])
		return items
	if value is Dictionary:
		var result: Dictionary = value.duplicate()
		for key: Variant in result: result[key] = source_value(result[key])
		return result
	return value

static func text(key: String) -> String:
	ensure_loaded()
	var translated := str(TranslationServer.translate(StringName(key)))
	if TranslationServer.get_locale().begins_with("en") and translated == key and not _messages.has(key) and not (_dynamic_messages.has(key) and _dynamic_messages[key] != key) and (_contains_han(key) or key.begins_with("LOC_")):
		_missing[key] = true
	else:
		_missing.erase(key)
	return translated

static func format_text(key: String, values: Variant) -> String:
	return text(key) % values

static func english_text(key: String) -> String:
	ensure_loaded()
	return _locale_text(key, "en")

static func chinese_text(key: String) -> String:
	ensure_loaded()
	return _locale_text(key, "zh_CN")

static func _locale_text(key: String, locale: String) -> String:
	var dynamic: Dictionary = _dynamic_messages if locale == "en" else _dynamic_chinese
	var messages: Dictionary = _messages if locale == "en" else _chinese_messages
	if dynamic.has(key):
		var translated := str(dynamic[key])
		if locale == "en" and translated == key and not messages.has(key) and _contains_han(key): _missing[key] = true
		return translated
	if messages.has(key): return str(messages[key])
	if locale == "en" and (_contains_han(key) or key.begins_with("LOC_")): _missing[key] = true
	return key

static func _format_arguments(values: Variant, positions: Array, locale: String) -> Variant:
	var result: Variant = values.duplicate() if values is Array else values
	for position: int in positions:
		var argument: Variant = result[position] if result is Array else result
		if argument is String or argument is StringName:
			var displayed := source(str(argument)) if locale.is_empty() else _locale_text(str(argument), locale)
			if result is Array: result[position] = displayed
			else: result = displayed
	return result

static func source_format(key: String, values: Variant, localize_arguments: Array = []) -> String:
	ensure_loaded()
	var count: int = values.size() if values is Array else 1
	for position: Variant in localize_arguments:
		if not position is int or position < 0 or position >= count:
			push_error("Source-format localization index is outside its explicit arguments.")
			return source(key) % values
	var canonical_values: Variant = _format_arguments(values, localize_arguments, "")
	var canonical := source(key) % canonical_values
	if _messages.has(key) or not localize_arguments.is_empty():
		var spec := {"kind":"format", "template":source(key), "arguments":canonical_values.duplicate(true) if canonical_values is Array else canonical_values, "positions":localize_arguments.duplicate()}
		_dynamic_specs[canonical] = spec
		_rebuild_dynamic(canonical, spec)
	return canonical

static func source_join(separator: String, values: Variant) -> String:
	ensure_loaded()
	var canonical_parts := PackedStringArray()
	for value: Variant in values: canonical_parts.append(source(str(value)))
	var canonical := source(separator).join(canonical_parts)
	var spec := {"kind":"join", "separator":source(separator), "arguments":Array(canonical_parts)}
	_dynamic_specs[canonical] = spec
	_rebuild_dynamic(canonical, spec)
	return canonical

static func _rebuild_dynamic(canonical: String, spec: Dictionary) -> void:
	var displays: Dictionary = {}
	for locale: String in ["zh_CN", "en"]:
		if spec.kind == "format":
			displays[locale] = _locale_text(spec.template, locale) % _format_arguments(spec.arguments, spec.positions, locale)
		elif spec.kind == "join":
			var parts := PackedStringArray()
			for value: Variant in spec.arguments: parts.append(_locale_text(str(value), locale))
			displays[locale] = _locale_text(spec.separator, locale).join(parts)
		elif spec.kind == "history":
			var arguments: Array = []
			for index in spec.arguments.size():
				var value := str(spec.arguments[index])
				var kind := str(spec.kinds[index])
				if kind == "scope":
					arguments.append(_locale_text(value, locale) if value == DeskLocalization.source("LOC_ALL_SYNTHETIC_AUDIENCES_ADD04D9F") else _locale_text("、", locale).join(value.split("、", false)))
				elif kind in ["preset", "family_label"]: arguments.append(_locale_text(value, locale))
				else: arguments.append(value)
			displays[locale] = _history_fill(_locale_text(spec.template, locale), arguments)
		else:
			displays[locale] = spec[locale]
	_install_display(canonical, displays.en, displays.zh_CN)

static func _install_display(canonical: String, english: String, chinese: String) -> void:
	if english != canonical: _missing.erase(canonical)
	_dynamic_messages[canonical] = english
	_dynamic_chinese[canonical] = chinese
	_translation.add_message(StringName(canonical), StringName(english))
	_chinese_translation.add_message(StringName(canonical), StringName(chinese))

static func register_display(canonical: String, displayed: String, chinese: String = "") -> void:
	ensure_loaded()
	var spec := {"kind":"literal", "en":displayed, "zh_CN":canonical if chinese.is_empty() else chinese}
	_dynamic_specs[canonical] = spec
	_rebuild_dynamic(canonical, spec)

static func prime_system_history(catalog: Resource, payload: Dictionary) -> void:
	# Only validated system records enter this decoder. Drafts, variant text and
	# player names are never decoded or added to a string-argument whitelist.
	ensure_loaded()
	var domains := {"group":{},"preset":{},"family":{},"variant":{}}
	for group: Resource in catalog.groups: domains.group[str(group.id)] = true
	for preset: Resource in catalog.presets: domains.preset[str(preset.title)] = true
	for id: String in payload.get("families",{}): domains.family[id] = true
	for variant: Dictionary in payload.get("variants",[]): domains.variant[str(variant.id)] = true
	var records: Array = []
	for key: String in ["events","pending_events"]: records.append_array(payload.get(key,[]))
	if not (payload.get("active_event",{}) as Dictionary).is_empty(): records.append(payload.active_event)
	for record: Dictionary in records:
		var source := str(record.get("effect_text",""))
		if not source.is_empty():
			var canonical_lines := source.split("\n",true)
			for line: String in canonical_lines: _history_effect_line(line,domains)
			source_join("\n",canonical_lines)
		_history_rewards(record)
	var status := str(payload.get("status",""))
	var country_title := str(payload.get("country_title",""))
	var deployed := DeskLocalization.source("LOC_DEPLOYED_TO_S_LATER_EXTERNAL_VERSIONS_CANNOT_CAE6EE96")
	if not country_title.is_empty() and status == deployed % country_title:
		source_format(deployed,country_title,[0])
	else:
		_history_known_format(status,DeskLocalization.source("LOC_NEW_RUN_D_MEME_MEME_TRADING_IS_74CC0B27"),["number"],domains)
		_history_known_format(status,DeskLocalization.source("LOC_NOT_ENOUGH_MEME_NEED_D_HAVE_D_46321C6B"),["number","number"],domains)
		_history_known_format(status,DeskLocalization.source("LOC_NOT_ENOUGH_MEME_RESERVE_D_FOR_FIRST_FE60303F"),["number"],domains)
	for entry: Dictionary in (payload.get("economy",{}) as Dictionary).get("transactions",[]):
		var reason := str(entry.get("reason",""))
		_history_known_format(reason,DeskLocalization.source("LOC_AUTHOR_OWNED_ADOPTION_MILESTONE_D_85F3EA92"),["number"],domains)
		source_format("H%d  %s%d Meme  %s → %d",[entry.hour,"+" if entry.delta >= 0 else "",entry.delta,reason,entry.balance],[3])

static func _history_effect_line(source: String, domains: Dictionary) -> String:
	var templates := [
		[DeskLocalization.source("LOC_S_ATTRACTION_MULTIPLIER_F_FOR_F_GAME_C6C49FBD"),["scope","number","number"]],
		[DeskLocalization.source("LOC_D_PREVIOUSLY_EXPOSED_NON_ADOPTERS_NOW_ADOPT_6CA6F2FB"),["number"]],
		[DeskLocalization.source("LOC_S_D_PREVIOUSLY_EXPOSED_NON_ADOPTERS_NOW_BA3D841D"),["scope","number"]],
		[DeskLocalization.source("LOC_EXTERNAL_REWRITES_SEMANTIC_DRIFT_FROM_THE_FIXED_35C3A40D"),["number"]],
		[DeskLocalization.source("LOC_S_FATIGUE_DECREASES_BY_F_AND_THE_40D510A3"),["scope","number"]],
		[DeskLocalization.source("LOC_S_S_VERSION_S_WAS_CREATED_BY_E8F39714"),["family_label","family","variant","creator"]],
		[DeskLocalization.source("LOC_S_IS_BEING_CARRIED_ON_BY_OTHERS_36686912"),["preset"]]]
	for item: Array in templates:
		if _history_known_format(source,item[0],item[1],domains): return english_text(source)
	for label: String in [DeskLocalization.source("LOC_TRUST_D1CD931B"),DeskLocalization.source("LOC_FATIGUE_9211F063")]:
		if not source.begins_with(label+"："): continue
		var changes := source.trim_prefix(label+"：").split("；",false)
		if changes.is_empty(): break
		var displayed := PackedStringArray()
		var valid := true
		for change: String in changes:
			if not _history_known_format(change,"%s %.2f→%.2f",["group","number","number"],domains):
				valid = false
				break
			displayed.append(english_text(change))
		if valid:
			source_format("%s：%s",[label,source_join("；",changes)],[0,1])
			return english_text(source)
	return english_text(source)

static func _history_rewards(record: Dictionary) -> void:
	var source := str(record.get("reward_text",""))
	if source.is_empty(): return
	var rules: Resource = load("res://data/rules/design_rules.tres")
	var canonical_parts := PackedStringArray()
	for reward: Dictionary in record.get("design_rewards",[]):
		var definition: Dictionary = rules.reward_resource(str(reward.get("kind","")),str(reward.get("id","")))
		canonical_parts.append(source_format("%s ×%d",[str(definition.get("title",reward.get("id",""))),int(reward.get("count",0))],[0]))
	var prefix := DeskLocalization.source("LOC_CLAIMED_9C9021A0") if bool(record.get("acknowledged",false)) else DeskLocalization.source("LOC_CLAIM_AFTER_COLLECTING_008ABC0C")
	var summary := source_join("、",canonical_parts)
	if source == prefix+summary: source_join("",[prefix,summary])
	else: english_text(source)

static func _history_known_format(canonical: String, template: String, kinds: Array, domains: Dictionary) -> bool:
	var canonical_template := source(template)
	var decoded := _history_decode(canonical,canonical_template)
	if not bool(decoded.get("matched",false)): return false
	var arguments: Array = decoded.arguments
	var tokens: PackedStringArray = decoded.tokens
	if arguments.size() != kinds.size(): return false
	for index in arguments.size():
		if not _history_allowed(str(arguments[index]),str(kinds[index]),str(tokens[index]),domains): return false
	var spec := {"kind":"history", "template":canonical_template, "arguments":arguments, "kinds":kinds.duplicate()}
	_dynamic_specs[canonical] = spec
	_rebuild_dynamic(canonical,spec)
	return true

static func _history_allowed(value: String, kind: String, token: String, domains: Dictionary) -> bool:
	if kind == "number":
		var expression := "^-?(?:0|[1-9][0-9]*)$" if token in ["%d","%.0f"] else "^-?(?:0|[1-9][0-9]*)\\.[0-9]{2}$" if token == "%.2f" else ""
		if expression.is_empty(): return false
		var matcher := RegEx.new()
		matcher.compile(expression)
		return matcher.search(value) != null
	if kind == "scope":
		if value == DeskLocalization.source("LOC_ALL_SYNTHETIC_AUDIENCES_ADD04D9F"): return true
		var groups := value.split("、",false)
		if groups.is_empty() or "、".join(groups) != value: return false
		for group: String in groups:
			if not domains.group.has(group): return false
		return true
	if kind == "creator": return domains.group.has(value) or value == "community"
	if kind == "family_label": return value in [DeskLocalization.source("LOC_NEW_FAMILY_A5AC4668"),DeskLocalization.source("LOC_VARIANT_OF_ORIGINAL_FAMILY_80F6D83C")]
	return domains.has(kind) and domains[kind].has(value)

static func _history_decode(source: String, template: String) -> Dictionary:
	var matcher := RegEx.new()
	matcher.compile("%(?:[-+ #0]*(?:[0-9]+|\\*)?(?:\\.(?:[0-9]+|\\*))?[scdiouxXfFeEgGv]|%)")
	var matches := matcher.search_all(template)
	var arguments: Array = []
	var tokens := PackedStringArray()
	var template_offset := 0
	var source_offset := 0
	for index in matches.size():
		var item: RegExMatch = matches[index]
		if item.get_string() == "%%": return {"matched":false}
		var literal := template.substr(template_offset,item.get_start()-template_offset)
		if source.substr(source_offset,literal.length()) != literal: return {"matched":false}
		source_offset += literal.length()
		var next_offset := item.get_end()
		var next_literal := template.substr(next_offset,matches[index+1].get_start()-next_offset) if index+1 < matches.size() else template.substr(next_offset)
		if next_literal.is_empty() and index+1 < matches.size(): return {"matched":false}
		var end := source.find(next_literal,source_offset) if not next_literal.is_empty() else source.length()
		if end < source_offset: return {"matched":false}
		arguments.append(source.substr(source_offset,end-source_offset))
		tokens.append(item.get_string())
		source_offset = end
		template_offset = next_offset
	var tail := template.substr(template_offset)
	if source.substr(source_offset) != tail or _history_fill(template,arguments) != source: return {"matched":false}
	return {"matched":true,"arguments":arguments,"tokens":tokens}

static func _history_fill(template: String, arguments: Array) -> String:
	var matcher := RegEx.new()
	matcher.compile("%(?:[-+ #0]*(?:[0-9]+|\\*)?(?:\\.(?:[0-9]+|\\*))?[scdiouxXfFeEgGv]|%)")
	var result := ""
	var offset := 0
	var index := 0
	for item: RegExMatch in matcher.search_all(template):
		result += template.substr(offset,item.get_start()-offset)+str(arguments[index])
		offset = item.get_end()
		index += 1
	return result+template.substr(offset)

static func validate_keyed_messages(messages: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if messages.is_empty(): errors.append("Translation table must contain at least one key.")
	var key_pattern := RegEx.new()
	key_pattern.compile("^[A-Za-z_][A-Za-z0-9_.]*$")
	var sources: Dictionary = {}
	for key: Variant in messages:
		if not key is String or key_pattern.search(str(key)) == null:
			errors.append("Translation keys must be stable ASCII identifiers: " + str(key))
			continue
		if not messages[key] is Dictionary:
			errors.append("Translation entry must contain source, zh_CN and en: " + str(key))
			continue
		var entry: Dictionary = messages[key]
		var valid := true
		for field: String in ["source", "zh_CN", "en"]:
			if not entry.get(field) is String or str(entry.get(field, "")).is_empty():
				errors.append("Translation " + str(key) + " requires nonempty " + field + ".")
				valid = false
		if not valid: continue
		for locale: String in ["zh_CN", "en"]:
			for error: String in validate_messages({str(entry.source):str(entry[locale])}):
				errors.append(str(key) + " [" + locale + "]: " + error)
		var canonical := str(entry.source)
		if sources.has(canonical) and messages[sources[canonical]] != entry:
			errors.append("Canonical source has conflicting translations: " + str(key))
		sources[canonical] = key
	return errors

static func validate_messages(messages: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key: Variant in messages:
		if not key is String or str(key).is_empty() or not messages[key] is String or str(messages[key]).is_empty():
			errors.append("Message sources and translations must be nonempty strings.")
			continue
		var source := str(key)
		var translated := str(messages[key])
		if _percent_tokens(source) != _percent_tokens(translated):
			errors.append("Percent placeholders differ for exact source: " + source)
		if _named_tokens(source) != _named_tokens(translated):
			errors.append("Named placeholders differ for exact source: " + source)
	return errors

static func bind_edit(edit: LineEdit, canonical: String, localize_default: bool = false) -> void:
	if localize_default: canonical = source(canonical)
	edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	edit.set_meta(EDIT_META, {"canonical":canonical, "localize_default":localize_default, "user_edited":false})
	if not edit.has_meta(EDIT_CONNECTED_META):
		edit.text_changed.connect(_edit_changed.bind(weakref(edit)))
		edit.set_meta(EDIT_CONNECTED_META, true)
	_refresh_edit(edit)

static func edit_value(edit: LineEdit) -> String:
	if edit.has_meta(EDIT_META):
		var state: Dictionary = edit.get_meta(EDIT_META)
		return str(state.canonical)
	return edit.text

static func bind_text_edit(edit: TextEdit, canonical: String, localize_default: bool = false) -> void:
	if localize_default: canonical = source(canonical)
	edit.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	edit.set_meta(EDIT_META, {"canonical":canonical, "localize_default":localize_default, "user_edited":false})
	if not edit.has_meta(EDIT_CONNECTED_META):
		edit.text_changed.connect(_text_edit_changed.bind(weakref(edit)))
		edit.set_meta(EDIT_CONNECTED_META, true)
	_refresh_text_edit(edit)

static func text_edit_value(edit: TextEdit) -> String:
	if edit.has_meta(EDIT_META):
		var state: Dictionary = edit.get_meta(EDIT_META)
		return str(state.canonical)
	return edit.text

static func lines(values: Array) -> PackedStringArray:
	var translated := PackedStringArray()
	for value: Variant in values: translated.append(text(str(value)))
	return translated

static func refresh_edits(root: Node) -> void:
	if root is LineEdit and root.has_meta(EDIT_META): _refresh_edit(root)
	elif root is TextEdit and root.has_meta(EDIT_META): _refresh_text_edit(root)
	for child: Node in root.get_children(): refresh_edits(child)

static func coverage_report() -> Dictionary:
	var missing: Array = _missing.keys()
	missing.sort()
	return {"initialized":_initialized, "locale":TranslationServer.get_locale(), "message_count":_records.size(), "dynamic_message_count":_dynamic_messages.size(), "table_paths":_table_paths.duplicate(), "load_error":_load_error, "load_errors":_load_errors.duplicate(), "last_reload_errors":_last_reload_errors.duplicate(), "missing_sources":missing}

static func clear_missing() -> void:
	_missing.clear()

static func _edit_changed(value: String, reference: WeakRef) -> void:
	var edit := reference.get_ref() as LineEdit
	if edit == null or not edit.has_meta(EDIT_META): return
	edit.set_meta(EDIT_META, {"canonical":value, "localize_default":false, "user_edited":true})

static func _refresh_edit(edit: LineEdit) -> void:
	var state: Dictionary = edit.get_meta(EDIT_META)
	var canonical := str(state.canonical)
	var displayed := text(canonical) if bool(state.localize_default) else canonical
	if edit.text == displayed: return
	var caret := edit.caret_column
	var signals_blocked := edit.is_blocking_signals()
	edit.set_block_signals(true)
	edit.text = displayed
	edit.set_block_signals(signals_blocked)
	edit.caret_column = mini(caret, displayed.length())

static func _text_edit_changed(reference: WeakRef) -> void:
	var edit := reference.get_ref() as TextEdit
	if edit == null or not edit.has_meta(EDIT_META): return
	edit.set_meta(EDIT_META, {"canonical":edit.text, "localize_default":false, "user_edited":true})

static func _refresh_text_edit(edit: TextEdit) -> void:
	var state: Dictionary = edit.get_meta(EDIT_META)
	var canonical := str(state.canonical)
	var displayed := text(canonical) if bool(state.localize_default) else canonical
	if edit.text == displayed: return
	var caret_line := edit.get_caret_line()
	var caret_column := edit.get_caret_column()
	var signals_blocked := edit.is_blocking_signals()
	edit.set_block_signals(true)
	edit.text = displayed
	edit.set_block_signals(signals_blocked)
	edit.set_caret_line(mini(caret_line,edit.get_line_count()-1))
	edit.set_caret_column(mini(caret_column,edit.get_line(edit.get_caret_line()).length()))

static func _contains_han(value: String) -> bool:
	for index in value.length():
		var code := value.unicode_at(index)
		if (code >= 0x3400 and code <= 0x9fff) or (code >= 0xf900 and code <= 0xfaff) or (code >= 0x20000 and code <= 0x323af): return true
	return false

static func _percent_tokens(value: String) -> PackedStringArray:
	var matcher := RegEx.new()
	matcher.compile("%(?:[-+ #0]*(?:[0-9]+|\\*)?(?:\\.(?:[0-9]+|\\*))?[scdiouxXfFeEgGv]|%)")
	var tokens := PackedStringArray()
	for found: RegExMatch in matcher.search_all(value): tokens.append(found.get_string())
	return tokens

static func _named_tokens(value: String) -> PackedStringArray:
	var matcher := RegEx.new()
	matcher.compile("\\{[A-Za-z_][A-Za-z0-9_]*\\}")
	var tokens := PackedStringArray()
	for found: RegExMatch in matcher.search_all(value): tokens.append(found.get_string())
	tokens.sort()
	return tokens
