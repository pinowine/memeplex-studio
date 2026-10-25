class_name DeskContextTrialSlip
extends Control

const Paper := preload("res://assets/image/textures/studio/desk/blank_print_paper.png")
const COMPONENTS := ["language", "group", "topics", "stance", "pragmatic", "access", "expression"]
const TITLES := {"language":"语言匹配", "group":"群体匹配", "topics":"话题匹配", "stance":"立场匹配", "pragmatic":"语用匹配", "access":"语境可达", "expression":"表达匹配"}
const INK := Color("384238")
const MUTED := Color("737968")

var _catalog: MemeDemoCatalog
var _rules: MemeDesignRules
var _draft: Dictionary = {}
var _country_id := ""
var _country_title := ""
var _components: Dictionary = {}
var _fitness: Dictionary = {}
var _previous_components: Dictionary = {}
var _last_change: Dictionary = {}
var _displayed_changes: Array = []
var _has_baseline := false
var _status := "unselected"
var _error := ""
var _change_sequence := 0
var _reset_count := 0
var _authored_target := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready(): queue_redraw()

func set_authored_target(source: String) -> void:
	_authored_target = source
	queue_redraw()

func _country_display_title() -> String:
	if _country_id.is_empty(): return DeskLocalization.text("未选落点")
	var key := _country_id+"_SHORT"
	var value := tr(key)
	return value if value != key else _country_title

func configure(catalog: MemeDemoCatalog, rules: MemeDesignRules) -> void:
	_catalog = catalog
	_rules = rules
	queue_redraw()

func set_draft(draft: Dictionary) -> void:
	_draft = draft.duplicate(true)
	queue_redraw()

func reset() -> void:
	_country_id = ""
	_country_title = ""
	_components.clear()
	_previous_components.clear()
	_fitness.clear()
	_last_change.clear()
	_displayed_changes.clear()
	_has_baseline = false
	_status = "unselected"
	_error = ""
	_change_sequence = 0
	_reset_count += 1
	queue_redraw()

func set_report(country_id: String, country_title: String, fitness: Dictionary, draft: Dictionary) -> void:
	set_draft(draft)
	if country_id.is_empty():
		if not _country_id.is_empty() or _has_baseline: reset()
		_status = "unselected"
		return
	var changed_country := country_id != _country_id
	if changed_country:
		_fitness.clear()
		_components.clear()
		_previous_components.clear()
		_last_change.clear()
		_displayed_changes.clear()
		_has_baseline = false
		_change_sequence = 0
	_country_id = country_id
	_country_title = country_title if not country_title.is_empty() else country_id
	var components := _read_components(fitness)
	if components.is_empty():
		_status = "unavailable"
		_error = "当前落点没有完整、有限的匹配分项。"
		queue_redraw()
		return
	_error = ""
	_fitness = fitness.duplicate(true)
	if not _has_baseline:
		_components = components
		_previous_components = components.duplicate(true)
		_has_baseline = true
		_status = "baseline"
		queue_redraw()
		return
	var deltas := {}
	var rows: Array = []
	for key: String in COMPONENTS:
		var delta := float(components[key]) - float(_components[key])
		if absf(delta) <= 0.000000001: continue
		deltas[key] = delta
		rows.append({"component":key, "title":TITLES[key], "before":float(_components[key]), "after":float(components[key]), "delta":delta, "direction":"up" if delta > 0 else "down"})
	if rows.is_empty():
		_components = components
		_status = "baseline" if _last_change.is_empty() else "changed"
		queue_redraw()
		return
	_previous_components = _components.duplicate(true)
	_components = components
	_change_sequence += 1
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(float(a.delta)) > absf(float(b.delta)))
	_last_change = {"country_id":_country_id, "sequence":_change_sequence, "before":_previous_components.duplicate(true), "after":_components.duplicate(true), "components":deltas, "changes":rows.duplicate(true)}
	_displayed_changes = rows.slice(0, mini(2, rows.size())).duplicate(true)
	_status = "changed"
	queue_redraw()

func _read_components(fitness: Dictionary) -> Dictionary:
	var raw: Variant = fitness.get("components")
	if not raw is Dictionary: return {}
	var result := {}
	for key: String in COMPONENTS:
		var value: Variant = raw.get(key)
		if not (value is float or value is int) or not is_finite(float(value)): return {}
		result[key] = float(value)
	return result

func _entry_title(kind: String, value: String) -> String:
	if value.is_empty(): return DeskLocalization.text("未放入")
	if kind == "group" and _catalog != null:
		for group: Resource in _catalog.get("groups"):
			if str(group.get("id")) == value: return DeskLocalization.text(str(group.get("title")))
	if _rules != null:
		var definitions: Resource = _rules.get("context_definitions")
		if definitions != null:
			for entry: Dictionary in definitions.get("entries"):
				if str(entry.get("kind", "")) == kind and str(entry.get("value", "")) == value: return DeskLocalization.text(str(entry.get("title", value)))
	return value

func _attachment_label(layer: String, text: String) -> String:
	var flags: Variant = _draft.get("context_layer_attachment", {})
	if flags is Dictionary and flags.get(layer) is bool and not flags[layer]:
		return text + DeskLocalization.text("（离体，不生效）")
	return text

func _context_labels() -> Dictionary:
	var topics := PackedStringArray()
	for id: String in _draft.get("topic_ids", []): topics.append(_entry_title("topic", id))
	var stance := DeskLocalization.text("未登记")
	if bool(_draft.get("political_known", false)):
		var point: Variant = _draft.get("political_position", Vector2.ZERO)
		if point is Vector2: stance = DeskLocalization.format_text("已登记 %.1f / %.1f", [point.x, point.y])
		elif point is Array and point.size() == 2: stance = DeskLocalization.format_text("已登记 %.1f / %.1f", [float(point[0]), float(point[1])])
		else: stance = DeskLocalization.text("已登记")
	var target := str(_draft.get("target", "")).strip_edges()
	if not _authored_target.is_empty() and target == _authored_target: target = DeskLocalization.text(target)
	return {"language":_attachment_label("language", _entry_title("language", str(_draft.get("language_id", "")))), "group":_attachment_label("group", _entry_title("group", str(_draft.get("group_id", "")))), "topics":_attachment_label("topics", "、".join(topics) if not topics.is_empty() else DeskLocalization.text("未放入")), "political_known":bool(_draft.get("political_known", false)), "stance":_attachment_label("stance", stance), "target":_attachment_label("pragmatic", target if not target.is_empty() else DeskLocalization.text("未填写对象"))}

func _change_text(row: Dictionary) -> String:
	var delta := float(row.delta)
	var number := String.num(delta, 8) if absf(delta) < 0.001 else "%.3f" % delta
	return DeskLocalization.text(str(row.title)) + (" ↑ +" if delta > 0 else " ↓ ") + number

func _status_text() -> String:
	if _status == "unselected": return DeskLocalization.text("未选落点 · 选定后再记录匹配")
	if _status == "unavailable": return DeskLocalization.text("暂无可比记录")
	if _status == "baseline": return DeskLocalization.text("当前基准 · 尚无修改前后差值")
	var changes := PackedStringArray()
	for row: Dictionary in _displayed_changes: changes.append(_change_text(row))
	return DeskLocalization.text("最近变化 · ") + "；".join(changes)

func _lines() -> Array:
	var context := _context_labels()
	var country := _country_display_title()
	if size.x >= 540:
		return [DeskLocalization.text("试配记录 / ") + country, DeskLocalization.text("语言 ") + str(context.language) + DeskLocalization.text(" · 群体 ") + str(context.group) + DeskLocalization.text(" · 话题 ") + str(context.topics), DeskLocalization.text("立场 ") + str(context.stance) + DeskLocalization.text(" · 语用对象 ") + str(context.target), _status_text()]
	var lines := [DeskLocalization.text("试配记录 / ") + country, DeskLocalization.text("语言 ") + str(context.language) + DeskLocalization.text(" · 群体 ") + str(context.group), DeskLocalization.text("话题 ") + str(context.topics), DeskLocalization.text("立场 ") + str(context.stance), DeskLocalization.text("语用对象 ") + str(context.target)]
	if _status == "changed":
		for row: Dictionary in _displayed_changes: lines.append(_change_text(row))
	else: lines.append(_status_text())
	return lines

func _draw_line(text: String, y: float, font_size: int, color: Color) -> void:
	var font := get_theme_default_font()
	var available := maxf(10, size.x - 24)
	var visible := text
	while visible.length() > 1 and font.get_string_size(visible, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available:
		visible = visible.left(visible.length() - 2) + "…"
	draw_string(font, Vector2(12, y), visible, HORIZONTAL_ALIGNMENT_LEFT, available, font_size, color)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_texture_rect(Paper, rect, false, Color("f0ead8"))
	draw_rect(rect.grow(-1), Color(0.27, 0.31, 0.24, 0.25), false, 1)
	var lines := _lines()
	var narrow := size.x < 540
	for index in lines.size():
		var y := 20.0 + float(index) * (21.0 if narrow else 20.0)
		_draw_line(str(lines[index]), y, 13 if index == 0 else 12, INK if index == 0 or index == lines.size() - 1 else MUTED)
	if narrow:
		_draw_line(DeskLocalization.text("匹配记录，非支持或采用预测。"), size.y - 12, 10, MUTED)
	else:
		draw_string(get_theme_default_font(), Vector2(maxf(12, size.x - 210), 19), DeskLocalization.text("匹配记录，非支持或采用预测。"), HORIZONTAL_ALIGNMENT_LEFT, 200, 10, MUTED)

func inspection() -> Dictionary:
	return {"comparison_available":_status == "changed" and not _last_change.is_empty(), "country_id":_country_id, "country_title":_country_title, "status":_status, "has_baseline":_has_baseline, "fitness":_fitness.duplicate(true), "components":_components.duplicate(true), "previous_components":_previous_components.duplicate(true), "last_change":_last_change.duplicate(true), "changed_components":_last_change.get("components", {}).duplicate(true), "displayed_changes":_displayed_changes.duplicate(true), "context":_context_labels(), "rendered_lines":_lines(), "is_prediction":false, "shows_success_rate":false, "paper_texture":Paper.resource_path, "change_sequence":_change_sequence, "reset_count":_reset_count, "error":DeskLocalization.text(_error),"display_country_title":_country_display_title(), "rect":Rect2(position, size), "layout_mode":"wide" if size.x >= 540 else "narrow"}
