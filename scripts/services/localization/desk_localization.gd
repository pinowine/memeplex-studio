class_name DeskLocalization
extends RefCounted

const DEFAULT_TABLES := ["res://localization/ui/desk_ui.en.json", "res://localization/content/desk_content.en.json"]
const EDIT_META := &"desk_localization_edit"
const EDIT_CONNECTED_META := &"desk_localization_edit_connected"

static var _initialized := false
static var _translation: Translation
static var _messages: Dictionary = {}
static var _dynamic_messages: Dictionary = {}
static var _missing: Dictionary = {}
static var _table_paths: Array[String] = []
static var _load_errors: Array[String] = []
static var _load_error: Error = OK

static func ensure_loaded(paths: Array = DEFAULT_TABLES) -> Error:
	if _initialized: return _load_error
	var combined: Dictionary = {}
	for value: Variant in paths:
		if not value is String:
			_record_load_error("Translation table path must be a string.", ERR_INVALID_PARAMETER)
			continue
		var path := str(value)
		_table_paths.append(path)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_record_load_error("Cannot open translation table: " + path, FileAccess.get_open_error())
			continue
		var parser := JSON.new()
		var error := parser.parse(file.get_as_text())
		file.close()
		if error != OK or not parser.data is Dictionary:
			_record_load_error("Translation table must contain a JSON object: " + path, ERR_PARSE_ERROR)
			continue
		var table: Dictionary = parser.data
		var invalid := validate_messages(table)
		if not invalid.is_empty():
			for message: String in invalid: _record_load_error(path + ": " + message, ERR_INVALID_DATA)
			continue
		for source: String in table:
			if combined.has(source) and combined[source] != table[source]:
				_record_load_error("Conflicting translation for exact source: " + source, ERR_INVALID_DATA)
			else:
				combined[source] = table[source]
	_messages = combined
	_translation = Translation.new()
	_translation.locale = "en"
	for source: String in _messages:
		_translation.add_message(StringName(source), StringName(_messages[source]))
	# Registration may notify ready presenters, so the service is initialized first.
	_initialized = true
	TranslationServer.add_translation(_translation)
	return _load_error

static func text(source: String) -> String:
	ensure_loaded()
	var translated := str(TranslationServer.translate(StringName(source)))
	if TranslationServer.get_locale().begins_with("en") and translated == source and not _messages.has(source) and not (_dynamic_messages.has(source) and _dynamic_messages[source] != source) and _contains_han(source):
		_missing[source] = true
	else:
		_missing.erase(source)
	return translated

static func format_text(source: String, values: Variant) -> String:
	return text(source) % values

static func english_text(source: String) -> String:
	ensure_loaded()
	if _dynamic_messages.has(source):
		var translated := str(_dynamic_messages[source])
		if translated == source and not _messages.has(source) and _contains_han(source): _missing[source] = true
		return translated
	if _messages.has(source): return str(_messages[source])
	if _contains_han(source): _missing[source] = true
	return source

static func source_format(source: String, values: Variant, localize_arguments: Array = []) -> String:
	var canonical := source % values
	ensure_loaded()
	if _messages.has(source) or not localize_arguments.is_empty():
		var english_values: Variant = values.duplicate() if values is Array else values
		for position: Variant in localize_arguments:
			var count: int = english_values.size() if english_values is Array else 1
			if not position is int or position < 0 or position >= count:
				push_error("Source-format localization index is outside its explicit arguments.")
				return canonical
			var argument: Variant = english_values[position] if english_values is Array else english_values
			if argument is String or argument is StringName:
				if english_values is Array: english_values[position] = english_text(str(argument))
				else: english_values = english_text(str(argument))
		var displayed := english_text(source) % english_values
		if _dynamic_messages.get(canonical) != displayed:
			if displayed != canonical: _missing.erase(canonical)
			_dynamic_messages[canonical] = displayed
			_translation.add_message(StringName(canonical), StringName(displayed))
	return canonical

static func source_join(separator: String, values: Variant) -> String:
	var canonical := separator.join(values)
	ensure_loaded()
	var parts := PackedStringArray()
	for value: Variant in values: parts.append(english_text(str(value)))
	var displayed := english_text(separator).join(parts)
	if _dynamic_messages.get(canonical) != displayed:
		if displayed != canonical: _missing.erase(canonical)
		_dynamic_messages[canonical] = displayed
		_translation.add_message(StringName(canonical),StringName(displayed))
	return canonical

static func register_display(source: String, displayed: String) -> void:
	ensure_loaded()
	if displayed != source: _missing.erase(source)
	_dynamic_messages[source] = displayed
	_translation.add_message(StringName(source),StringName(displayed))

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
			var displayed_lines := PackedStringArray()
			for line: String in source.split("\n",true): displayed_lines.append(_history_effect_line(line,domains))
			register_display(source,"\n".join(displayed_lines))
		_history_rewards(record)
	var status := str(payload.get("status",""))
	var country_title := str(payload.get("country_title",""))
	var deployed := "已投放到 %s；后续外部版本不能直接编辑。"
	if not country_title.is_empty() and status == deployed % country_title:
		register_display(status,english_text(deployed) % english_text(country_title))
	else:
		_history_known_format(status,"新局：%d Meme；模因交易不可用。",["number"],domains)
		_history_known_format(status,"Meme 点数不足：需要 %d，当前 %d。",["number","number"],domains)
		_history_known_format(status,"Meme 点数不足，首次投放需预留 %d 点。",["number"],domains)
	for entry: Dictionary in (payload.get("economy",{}) as Dictionary).get("transactions",[]):
		var reason := str(entry.get("reason",""))
		_history_known_format(reason,"作者归属采用里程碑 %d",["number"],domains)
		source_format("H%d  %s%d Meme  %s → %d",[entry.hour,"+" if entry.delta >= 0 else "",entry.delta,reason,entry.balance],[3])

static func _history_effect_line(source: String, domains: Dictionary) -> String:
	var templates := [
		["%s：吸引系数 ×%.2f，持续 %.0f 游戏小时；总注意力预算不增加。",["scope","number","number"]],
		["已曝光而未采用者新增采用 %d。",["number"]],
		["%s：已曝光而未采用者中新增采用 %d；未凭空增加曝光。",["scope","number"]],
		["外部改写相对固定家族锚点的语义偏移设为 %.2f；下一次改写按分家规则处理。",["number"]],
		["%s：疲劳降低 %.2f，旧表达重新进入使用；不恢复对外部分家的控制。",["scope","number"]],
		["%s %s；版本 %s 由 %s 制作，玩家不可编辑；来源保留。",["family_label","family","variant","creator"]],
		["%s 正被其他人接续传播；发声者没有署名，你还无法接管它。",["preset"]]]
	for item: Array in templates:
		if _history_known_format(source,item[0],item[1],domains): return english_text(source)
	for label: String in ["信任","疲劳"]:
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
			register_display(source,english_text("%s：%s") % [english_text(label),english_text("；").join(displayed)])
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
	var prefix := "已领取：" if bool(record.get("acknowledged",false)) else "收录后领取："
	var summary := source_join("、",canonical_parts)
	if source == prefix+summary: register_display(source,english_text(prefix)+english_text(summary))
	else: english_text(source)

static func _history_known_format(source: String, template: String, kinds: Array, domains: Dictionary) -> bool:
	var decoded := _history_decode(source,template)
	if not bool(decoded.get("matched",false)): return false
	var arguments: Array = decoded.arguments
	var tokens: PackedStringArray = decoded.tokens
	if arguments.size() != kinds.size(): return false
	var displayed: Array = []
	for index in arguments.size():
		var value := str(arguments[index])
		var kind := str(kinds[index])
		if not _history_allowed(value,kind,str(tokens[index]),domains): return false
		if kind == "scope":
			displayed.append(english_text(value) if value == "全部合成人群" else english_text("、").join(value.split("、",false)))
		elif kind in ["preset","family_label"]: displayed.append(english_text(value))
		else: displayed.append(value)
	var english_template := english_text(template)
	if _percent_tokens(english_template) != tokens: return false
	register_display(source,_history_fill(english_template,displayed))
	return true

static func _history_allowed(value: String, kind: String, token: String, domains: Dictionary) -> bool:
	if kind == "number":
		var expression := "^-?(?:0|[1-9][0-9]*)$" if token in ["%d","%.0f"] else "^-?(?:0|[1-9][0-9]*)\\.[0-9]{2}$" if token == "%.2f" else ""
		if expression.is_empty(): return false
		var matcher := RegEx.new()
		matcher.compile(expression)
		return matcher.search(value) != null
	if kind == "scope":
		if value == "全部合成人群": return true
		var groups := value.split("、",false)
		if groups.is_empty() or "、".join(groups) != value: return false
		for group: String in groups:
			if not domains.group.has(group): return false
		return true
	if kind == "creator": return domains.group.has(value) or value == "community"
	if kind == "family_label": return value in ["新家族","原家族变体"]
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
	return {"initialized":_initialized, "locale":TranslationServer.get_locale(), "message_count":_messages.size(), "dynamic_message_count":_dynamic_messages.size(), "table_paths":_table_paths.duplicate(), "load_error":_load_error, "load_errors":_load_errors.duplicate(), "missing_sources":missing}

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

static func _record_load_error(message: String, error: Error) -> void:
	_load_errors.append(message)
	if _load_error == OK: _load_error = error
	push_error(message)
