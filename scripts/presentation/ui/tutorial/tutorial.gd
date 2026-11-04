class_name DeskTutorial
extends Control

signal step_changed(id: String, step: Dictionary)
signal finished(skipped: bool)
signal focus_changed(active: bool)

const TEMPLATE = preload("res://scenes/ui/tutorial/tutorial.tscn")
const PaperStyle = preload("res://scripts/presentation/studio/paper/desk_paper_style.gd")
const Arrow = preload("res://scripts/presentation/ui/tutorial/tutorial_arrow.gd")
const CARD_MARGIN := 20.0
const TARGET_GAP := 52.0
const MAX_ARROW_LENGTH := 72.0

var _steps: Array[Dictionary] = []
var _index := 0
var _active := false
var _completed := false
var _blocked := false
var _hint_only := false
var _provider := Callable()
var _avoid_provider := Callable()
var _overview_provider := Callable()
var _return_overview := false
var _avoid_rects: Array[Rect2] = []
var _target := Rect2()
var _ui: Control
var _history: Array[Dictionary] = []
var _display_index := 0
var _transition: Tween
var _transitioning := false
var _appearance := 0.0
var _card_position := Vector2.ZERO
var _arrow_from := Vector2.ZERO
var _arrow_to := Vector2.ZERO
var _arrow_visible := false
var _arrow: Node2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if theme == null: theme = load("res://data/presentation/ui/demo_theme.tres")
	_ui = TEMPLATE.instantiate()
	add_child(_ui)
	_arrow = Arrow.new()
	_arrow.name = "GuideArrow"
	add_child(_arrow)
	_arrow.hide()
	_ui.get_node("Card/Content/Actions/Continue").pressed.connect(advance)
	_ui.get_node("Card/Content/Actions/Skip").pressed.connect(skip)
	PaperStyle.apply_buttons(_ui)
	if _steps.is_empty(): _steps = default_steps()
	resized.connect(_refresh)
	hide()

func configure(steps: Array[Dictionary] = [], target_provider: Callable = Callable(), avoid_provider: Callable = Callable(), overview_provider: Callable = Callable()) -> void:
	_steps = default_steps() if steps.is_empty() else steps.duplicate(true)
	_provider = target_provider
	_avoid_provider = avoid_provider
	_overview_provider = overview_provider
	_index = clampi(_index, 0, _steps.size() - 1)
	_refresh()

func set_target_provider(provider: Callable) -> void:
	_provider = provider
	_refresh()

func begin() -> void:
	_index = 0
	_history.clear()
	_completed = false
	_hint_only = false
	_open()

func set_step(id: String) -> bool:
	for index in _steps.size():
		if str(_steps[index].get("id", "")) == id:
			_index = index
			_hint_only = false
			_open()
			return true
	return false

func observe_action(id: String, payload: Dictionary = {}) -> bool:
	if not _active or _blocked or _hint_only: return false
	var step := _steps[_index]
	if str(step.get("action", "continue")) != id: return false
	for key: Variant in step.get("match", {}):
		if payload.get(key) != step.match[key]: return false
	_history.append({"step": str(step.id), "action": id, "payload": payload.duplicate(true)})
	_advance()
	return true

func advance() -> void:
	if not _active or _blocked or _transitioning: return
	if _hint_only:
		_close(false)
		return
	observe_action("continue")

func skip() -> void:
	if not _active: return
	_close(true)

func reenter_hint() -> void:
	_hint_only = _completed
	_open()

func set_interaction_blocked(blocked: bool) -> void:
	if _blocked == blocked: return
	_blocked = blocked
	_refresh()

func _open() -> void:
	_active = true
	show()
	_present_step()
	focus_changed.emit(true)
	step_changed.emit(str(_steps[_index].id), _steps[_index].duplicate(true))

func _advance() -> void:
	if _index == _steps.size() - 1:
		_completed = true
		_close(false)
		return
	_index += 1
	_present_step()
	step_changed.emit(str(_steps[_index].id), _steps[_index].duplicate(true))

func _close(skipped: bool) -> void:
	_active = false
	_stop_transition()
	_transitioning = true
	_transition = create_tween()
	_transition.tween_method(_set_appearance, _appearance, 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_transition.tween_callback(func():
		_transitioning = false
		hide())
	focus_changed.emit(false)
	finished.emit(skipped)

func _stop_transition() -> void:
	if _transition != null and _transition.is_valid(): _transition.kill()

func _present_step() -> void:
	_stop_transition()
	_transitioning = true
	_transition = create_tween()
	if _appearance > 0.01:
		_transition.tween_method(_set_appearance, _appearance, 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_transition.tween_callback(func():
		_display_index = _index
		_set_appearance(0.0))
	_transition.tween_method(_set_appearance, 0.0, 1.0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_callback(func():
		_transitioning = false
		_refresh())

func _set_appearance(value: float) -> void:
	_appearance = value
	_refresh()

func _process(_delta: float) -> void:
	if visible: _refresh()

func _refresh() -> void:
	if not is_instance_valid(_ui) or _steps.is_empty(): return
	var english := TranslationServer.get_locale().begins_with("en")
	_display_index = clampi(_display_index, 0, _steps.size() - 1)
	var step := _steps[_display_index]
	_return_overview = _overview_provider.is_valid() and bool(_overview_provider.call(str(step.get("target", ""))))
	_ui.get_node("Card/Content/Title").text = DeskLocalization.text(str(step.get("title_en", step.get("title", "")))) if english else str(step.get("title", ""))
	_ui.get_node("Card/Content/Body").text = DeskLocalization.text(str(step.get("text_en", step.get("text", "")))) if english else str(step.get("text", ""))
	var next: Button = _ui.get_node("Card/Content/Actions/Continue")
	next.text = ("Close hint" if english else "收起提示") if _hint_only else ("Continue" if english else "继续")
	var requires_action := not _hint_only and str(step.get("action", "continue")) != "continue"
	next.disabled = not _active or _blocked or _transitioning or requires_action
	_ui.get_node("Card/Content/Actions/Skip").text = "Skip guide" if english else "跳过讲解"
	_ui.get_node("Card/Content/Actions/Skip").disabled = not _active or _blocked
	_target = Rect2()
	if _provider.is_valid() and not str(step.get("target", "")).is_empty():
		var target: Variant = _provider.call(str(step.target))
		if target is Control and target.is_visible_in_tree():
			var transform: Transform2D = get_global_transform_with_canvas().affine_inverse() * target.get_global_transform_with_canvas()
			_target = transform * Rect2(Vector2.ZERO, target.size)
		elif target is Rect2: _target = get_global_transform_with_canvas().affine_inverse() * target
	# Offscreen or missing targets never receive a speculative pointer.
	_target = _target.intersection(Rect2(Vector2.ZERO, size))
	_avoid_rects.clear()
	if _avoid_provider.is_valid():
		var reserved: Variant = _avoid_provider.call()
		if reserved is Array:
			var inverse := get_global_transform_with_canvas().affine_inverse()
			for rectangle: Variant in reserved:
				if rectangle is Rect2 and rectangle.has_area():
					_avoid_rects.append(inverse * rectangle)
	var card: Control = _ui.get_node("Card")
	var compact := size.x < 900 or size.y < 560
	var width := minf(600 if compact else 500, size.x - CARD_MARGIN * 2.0)
	var minimum_width := 268.0 if compact else 344.0
	# The live phone paper reserves the right side, including while it slides in.
	for rectangle: Rect2 in _avoid_rects:
		if rectangle.get_center().x > size.x * .5:
			width = minf(width, maxf(minimum_width, rectangle.position.x - CARD_MARGIN * 2.0 - TARGET_GAP))
	card.get_node("Portrait67").visible = not compact
	card.get_node("Speaker").visible = not compact
	var title: Label = card.get_node("Content/Title")
	var body: Label = card.get_node("Content/Body")
	var title_size := 18 if compact else 21
	var body_size := 14 if compact else 17
	if title.get_theme_font_size("font_size") != title_size: title.add_theme_font_size_override("font_size", title_size)
	if body.get_theme_font_size("font_size") != body_size: body.add_theme_font_size_override("font_size", body_size)
	var waiting: Label = _ui.get_node("Card/Content/Waiting")
	waiting.visible = not _blocked and (_return_overview or (requires_action and not compact))
	if _return_overview:
		waiting.text = "Press Esc or click empty space to return to the main desk." if english else "按 Esc 或单击空白处，回到主桌面。"
	else:
		waiting.text = "Follow the current instruction." if english else "按当前提示完成操作。"
	var minimum_height := 128.0 if compact else 190.0
	card.size = Vector2(width, minimum_height)
	var content: Control = card.get_node("Content")
	content.position = Vector2(14, 14) if compact else Vector2(94, 18)
	var separation := 6 if compact else 8
	if content.get_theme_constant("separation") != separation: content.add_theme_constant_override("separation", separation)
	var padding := Vector2(28, 28) if compact else Vector2(112, 36)
	content.size = card.size - padding
	body.size.x = content.size.x
	waiting.size.x = content.size.x
	card.size.y = maxf(minimum_height, content.get_combined_minimum_size().y + padding.y)
	content.size = card.size - padding
	_card_position = _place_card(card.size)
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2.ONE * lerpf(0.94, 1.0, _appearance)
	card.position = _card_position + Vector2(0, (1.0 - _appearance) * 12.0)
	_ui.modulate.a = _appearance
	_update_arrow(Rect2(card.position + card.pivot_offset * (Vector2.ONE - card.scale), card.size * card.scale))
	queue_redraw()

func _place_card(dimensions: Vector2) -> Vector2:
	var candidates: Array[Vector2] = []
	if _target.has_area():
		# Three alignments per edge keep the bubble close even near a screen corner.
		for alignment: float in [0.5, 0.0, 1.0]:
			var x := lerpf(_target.position.x, _target.end.x, alignment) - dimensions.x * alignment
			var y := lerpf(_target.position.y, _target.end.y, alignment) - dimensions.y * alignment
			candidates.append(Vector2(_target.end.x + TARGET_GAP, y))
			candidates.append(Vector2(_target.position.x - dimensions.x - TARGET_GAP, y))
			candidates.append(Vector2(x, _target.position.y - dimensions.y - TARGET_GAP))
			candidates.append(Vector2(x, _target.end.y + TARGET_GAP))
	else:
		# General dialogue has a quiet resting position and no implied target.
		candidates.append(Vector2((size.x - dimensions.x) * 0.5, size.y - dimensions.y - 36))
		candidates.append(Vector2(CARD_MARGIN, size.y - dimensions.y - 36))
		candidates.append(Vector2(CARD_MARGIN, CARD_MARGIN))
	var best := Vector2.ZERO
	var best_score := INF
	var lower := Vector2.ONE * CARD_MARGIN
	var upper := (size - dimensions - lower).max(lower)
	for candidate: Vector2 in candidates:
		var point := candidate.clamp(lower, upper)
		var rectangle := Rect2(point, dimensions)
		var score := 0.0
		if _target.has_area():
			score += rectangle.intersection(_target.grow(12)).get_area() * 100.0
			var endpoints := _nearest_edges(rectangle, _target)
			score += absf(endpoints[0].distance_to(endpoints[1]) - TARGET_GAP) * 6.0
		for reserved: Rect2 in _avoid_rects:
			score += rectangle.intersection(reserved.grow(12)).get_area() * 100.0
		# Small stability bias prevents flipping sides while the camera settles.
		score += point.distance_to(_card_position) * 0.01 if _target.has_area() else float(candidates.find(candidate))
		if score < best_score:
			best_score = score
			best = point
	return best

func _nearest_edges(card: Rect2, target: Rect2) -> PackedVector2Array:
	var from := card.get_center()
	var to := target.get_center()
	if card.end.x <= target.position.x:
		from.x = card.end.x
		to.x = target.position.x
	elif target.end.x <= card.position.x:
		from.x = card.position.x
		to.x = target.end.x
	else:
		from.x = clampf(target.get_center().x, card.position.x + 20, card.end.x - 20)
		to.x = clampf(from.x, target.position.x, target.end.x)
	if card.end.y <= target.position.y:
		from.y = card.end.y
		to.y = target.position.y
	elif target.end.y <= card.position.y:
		from.y = card.position.y
		to.y = target.end.y
	else:
		from.y = clampf(target.get_center().y, card.position.y + 20, card.end.y - 20)
		to.y = clampf(from.y, target.position.y, target.end.y)
	return PackedVector2Array([from, to])

func _update_arrow(card: Rect2) -> void:
	_arrow_visible = false
	_arrow.visible = false
	if not _target.has_area() or card.intersects(_target) or _blocked: return
	var endpoints := _nearest_edges(card, _target)
	var direction := (endpoints[1] - endpoints[0]).normalized()
	_arrow_to = endpoints[1] - direction * 7.0
	var length := minf(MAX_ARROW_LENGTH, endpoints[0].distance_to(_arrow_to) - 5.0)
	_arrow_from = _arrow_to - direction * length
	_arrow_visible = length >= 18.0
	_arrow.visible = _arrow_visible
	# The pointer stays visible while the dialogue card changes targets.
	_arrow.modulate.a = 1.0 if _active else _appearance
	if _arrow_visible: _arrow.point_to(_arrow_to, direction.angle(), length)

func handles_viewport_point(point: Vector2) -> bool:
	if not _active or not is_visible_in_tree() or not point.is_finite(): return false
	for path: String in ["Card/Content/Actions/Continue", "Card/Content/Actions/Skip"]:
		var button: Button = _ui.get_node(path)
		if not button.is_visible_in_tree(): continue
		var local := button.get_global_transform_with_canvas().affine_inverse() * point
		if Rect2(Vector2.ZERO, button.size).has_point(local): return true
	return false

func inspection() -> Dictionary:
	return {"active": _active, "step": {} if _steps.is_empty() else _steps[_index].duplicate(true), "index": _index, "count": _steps.size(), "completed": _completed, "blocked": _blocked, "hint_only": _hint_only, "target_rect": _target, "history": _history.duplicate(true), "fixed_wait_seconds": 0, "blocks_desktop": false, "portrait": "res://assets/image/textures/studio/desk/portrait_67.png", "card_rect": _ui.get_node("Card").get_rect() if _ui != null else Rect2(), "avoid_rects": _avoid_rects.duplicate(), "arrow_visible": _arrow_visible, "arrow_length": _arrow_from.distance_to(_arrow_to) if _arrow_visible else 0.0, "arrow":_arrow.inspection() if _arrow != null else {}, "return_overview":_return_overview, "transitioning": _transitioning, "appearance": _appearance, "display_index": _display_index}

func default_steps() -> Array[Dictionary]:
	return [
		{"id":"identity", "title":"一份工作", "text":"你是工作室的印刷编辑。能改稿，不能替别人理解它。后者的工资也没人发。", "title_en":"A job", "text_en":"You are the print editor. You can revise a message, not understand it for other people. Nobody pays for the latter.", "action":"continue"},
		{"id":"work", "title":"你的稿件", "text":"把表达装进模因，调整它说给谁、说什么、怎样说。投放之后，读者和竞争者会替你继续改。通常不先征求意见。", "title_en":"Your copy", "text_en":"Build an expression, decide whom it addresses and how it speaks. Readers and competitors will revise it after publication. Usually without asking.", "action":"continue"},
		{"id":"goals", "title":"四种收工方式", "text":"占有世界；让失控谱系独自活下去；与竞争者达到均衡；或让多个版本共同扩散。任意一种成立就能收工。不是要求你同时加四班。", "title_en":"Four ways out", "text_en":"Own the world; let an autonomous lineage survive; reach equilibrium with rivals; or spread through several distinct versions. Any one ends the job. Four overtime shifts are not required.", "action":"continue"},
		{"id":"pickup", "title":"电话响了", "text":"接起电话。三个起始稿件都已备好。先选一个，不必填一整份报表。", "title_en":"The phone", "text_en":"Pick up. Three starter manuscripts are ready. Choose one; a full report is not required.", "action":"phone_pickup", "target":"fax/pickup"},
		{"id":"starter", "title":"领一份稿", "text":"在电话对话里选一个起始模因。选择是稿件，不是替你决定以后的一切。", "title_en":"Take a manuscript", "text_en":"Choose one starter in the call. It gives you a manuscript, not every decision for the rest of your life.", "action":"starter_chosen", "target":"fax/options"},
		{"id":"hangup", "title":"结束通话", "text":"挂断，回到桌面。电话不会替你印东西。", "title_en":"Hang up", "text_en":"Hang up and return to the desk. The telephone will not print it for you.", "action":"startup_finished", "target":"fax/hangup"},
		{"id":"machines", "title":"传真与情报", "text":"传真收情报与卡牌。点纸堆露出的页签，就能翻看历史事件。", "title_en":"Incoming intelligence", "text_en":"The fax receives intelligence and cards. Its exposed paper tabs reopen past events.", "action":"continue", "target":"desktop/fax"},
		{"id":"printer", "title":"打印机", "text":"打印机留下工作记录。世界会忘事，它负责记账。", "title_en":"The printer", "text_en":"The printer keeps your work record. The world forgets; it keeps the books.", "action":"continue", "target":"desktop/printer"},
		{"id":"monitor", "title":"显示器", "text":"显示器盯着你的模因和点数。它没有加班费，所以一直盯着。", "title_en":"The monitor", "text_en":"The monitor watches your memes and points. It has no overtime pay, so it keeps watching.", "action":"continue", "target":"desktop/monitor"},
		{"id":"speed", "title":"时间旋钮", "text":"试一下暂停、正常或快进。情报会继续打印，不用停下来盖章。读得快也不会多发奖励。", "title_en":"Time controls", "text_en":"Try pause, normal or fast. Messages keep printing without a stamp. Reading faster does not earn an extra reward.", "action":"speed_changed", "target":"speed"},
		{"id":"edit", "title":"编辑纸", "text":"抽出编辑纸。补丁纸夹在回形针上；拿下纸片就卸下。左边的神经元会和它一起改变。", "title_en":"Editing paper", "text_en":"Pull out the editing sheet. Patch papers clip into place; taking a paper off uninstalls it. Its neuron changes the expression on the left.", "action":"sheet_selected", "match":{"id":"edit"}, "target":"sheet/edit"},
		{"id":"module", "title":"夹一个补丁", "text":"把自己的补丁纸夹进空夹子。纸片不是重新选基模。原稿还得由你负责。", "title_en":"Clip a patch", "text_en":"Put an owned patch paper into a free clip. A patch is not a new core. You remain responsible for the manuscript.", "action":"module_installed", "target":"editor/clips"},
		{"id":"context", "title":"语境切片", "text":"抽出培养纸，看看各个语境分区。语言、群体、话题放卡牌；立场与语用沿坐标轴调整。离开起点花筹码，退回起点归还。", "title_en":"Context slice", "text_en":"Pull out the context sheet. Language, groups and topics take cards; stance and pragmatics move along their axes. Moving out spends tokens, returning refunds them.", "action":"sheet_selected", "match":{"id":"cultivate"}, "target":"sheet/cultivate"},
		{"id":"context_item", "title":"给表达一个语境", "text":"把一个可用物件放进对应空位。拆装会改稿，不会替世界改口。", "title_en":"Give it context", "text_en":"Put an available object in its matching free slot. Changing the manuscript does not rewrite the world.", "action":"context_installed", "target":"context/slot"},
		{"id":"spread", "title":"传播纸", "text":"抽出传播纸。能力沿着同一棵树长出来，不是另一份采购清单。", "title_en":"Propagation sheet", "text_en":"Pull out the propagation sheet. Abilities grow along one connected tree, not a second shopping list.", "action":"sheet_selected", "match":{"id":"spread"}, "target":"sheet/spread"},
		{"id":"skill", "title":"买一种能力", "text":"选一个付得起的能力。购买成功会作用于稿件。价格是真价格，后悔不是退款申请。", "title_en":"Buy an ability", "text_en":"Choose an affordable ability. A successful purchase affects the manuscript. Its price is real; regret is not a refund request.", "action":"skill_purchased", "target":"spread/skill"},
		{"id":"publish", "title":"送去印刷", "text":"回编辑纸确认稿件，再决定投放国家。第一次发布免费。免费的是印刷，不是别人一定会采用。", "title_en":"Send to print", "text_en":"Confirm the manuscript on the editing sheet, then select a country. First publication is free. Adoption is not included.", "action":"publish_requested", "target":"editor/publish"},
		{"id":"country", "title":"选一个落点", "text":"在地图纸上选国家。不同人群与语境会影响采用；国界不是情绪的围墙。", "title_en":"Choose a location", "text_en":"Choose a country on the map. Audiences and context affect adoption. Borders are not walls around emotions.", "action":"country_selected", "target":"map/country"},
		{"id":"confirm", "title":"开始流通", "text":"点击国家上方带对勾的气泡。气泡破裂后，稿件开始流传。新事件会和卡牌一起打印出来；把卡牌拖到桌面，再装进对应槽位。", "title_en":"Into circulation", "text_en":"Click the checkmark bubble above the country. It pops and your manuscript starts circulating. New events and cards print together; drag the cards onto the desk, then into their matching slots.", "action":"published", "target":"map/confirm"}
	]

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()
