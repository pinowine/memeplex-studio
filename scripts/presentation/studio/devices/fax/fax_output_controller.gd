extends Node

signal state_changed
signal progress_changed
signal pages_changed
signal read_completed(instance_id: String)
signal output_started(record: Dictionary, page: Control)
signal output_delivered(record: Dictionary, page: Control)

const OutputPage := preload("res://scripts/presentation/studio/devices/fax/desk_fax_output_page.gd")
const StationView := preload("res://scripts/presentation/studio/devices/fax/fax_station_view.gd")
var pending_events: Array[Dictionary] = []
var active_event: Dictionary = {}
var received_event_ids: Dictionary = {}
var read_event_ids := PackedStringArray()
var last_read: Dictionary = {}
var event_state := "idle"
var output_pages: Array[Control] = []
var feeding_page: Control
var output_geometry: Dictionary = {}
var continuous_output := false
var last_error := ""
var feed_progress := 0.0:
	set(value):
		feed_progress = clampf(value, 0.0, 1.0)
		sync_current_page()
		progress_changed.emit()
var _host: Control
var _page_theme: Theme
var _measure_output: Callable
var _feed_tween: Tween
var _feed_duration := .65
var _retract_duration := .55
var _blocked := false
var _dispatching_completion := false

func configure(host: Control, page_theme: Theme, measure_output: Callable) -> void:
	_host = host
	_page_theme = page_theme
	_measure_output = measure_output

func set_durations(feed: float, retract: float) -> void:
	_feed_duration = clampf(feed, .01, 10.0)
	_retract_duration = clampf(retract, .01, 10.0)

func set_page_theme(value: Theme) -> void:
	_page_theme = value
	for page: Control in all_pages(): page.theme = value

func set_continuous_output(value: bool) -> void:
	continuous_output = value
	if value and _feed_tween != null and _feed_tween.is_valid(): _feed_tween.play()

func enqueue(event: Dictionary) -> bool:
	last_error = ""
	var id := str(event.get("instance_id", "")).strip_edges()
	if id.is_empty() or not event.get("title") is String or not event.get("narrative") is String:
		last_error = "情报缺少 instance_id、标题或正文。"
		return false
	if bool(event.get("acknowledged", false)) or received_event_ids.has(id): return false
	received_event_ids[id] = true
	pending_events.append(event.duplicate(true))
	return true

func dispatch_pending() -> void:
	if active_event.is_empty() and not _dispatching_completion: _start_next()

func busy() -> bool:
	return not active_event.is_empty() or not pending_events.is_empty() or _dispatching_completion

func set_blocked(value: bool) -> void:
	_blocked = value
	if not continuous_output and _feed_tween != null and _feed_tween.is_valid():
		if value: _feed_tween.pause()
		else: _feed_tween.play()
	if not value and event_state == "retracting" and feed_progress == 0.0: _finish_read.call_deferred()

func retract() -> bool:
	if continuous_output or event_state != "ready" or active_event.is_empty(): return false
	event_state = "retracting"
	state_changed.emit()
	_kill_feed_tween()
	_feed_tween = create_tween()
	_feed_tween.tween_property(self, "feed_progress", 0.0, _retract_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_feed_tween.tween_callback(_finish_read)
	if _blocked: _feed_tween.pause()
	return true

func _start_next() -> void:
	if pending_events.is_empty():
		event_state = "idle"
		state_changed.emit()
		return
	active_event = pending_events.pop_front()
	event_state = "feeding"
	feed_progress = 0.0
	if continuous_output: _begin_physical_output()
	state_changed.emit()
	_kill_feed_tween()
	_feed_tween = create_tween()
	_feed_tween.tween_property(self, "feed_progress", 1.0, _feed_duration * float(output_geometry.get("duration_scale", 1.0))).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_feed_tween.tween_callback(_feed_finished)
	if _blocked and not continuous_output: _feed_tween.pause()

func _feed_finished() -> void:
	if not continuous_output:
		event_state = "ready"
		state_changed.emit()
		return
	if active_event.is_empty() or not is_instance_valid(feeding_page): return
	var page := feeding_page
	sync_current_page()
	page.finish_output(output_pages.size())
	output_pages.append(page)
	feeding_page = null
	event_state = "delivered"
	pages_changed.emit()
	output_delivered.emit(active_event.duplicate(true), page)
	_finish_read()

func _finish_read() -> void:
	if active_event.is_empty() or event_state not in ["retracting", "delivered"] or (_blocked and not continuous_output): return
	var id := str(active_event.instance_id)
	last_read = active_event.duplicate(true)
	read_event_ids.append(id)
	active_event = {}
	event_state = "idle"
	# A completion handler can enqueue the next event synchronously.
	_dispatching_completion = true
	state_changed.emit()
	read_completed.emit(id)
	_dispatching_completion = false
	dispatch_pending()

func all_pages() -> Array[Control]:
	var pages: Array[Control] = output_pages.duplicate()
	if is_instance_valid(feeding_page): pages.append(feeding_page)
	return pages

func restore_page_order() -> void:
	for index in output_pages.size():
		output_pages[index].z_index = 0
		_host.move_child(output_pages[index], index)

func reset() -> void:
	_kill_feed_tween()
	pending_events.clear()
	active_event.clear()
	received_event_ids.clear()
	read_event_ids.clear()
	last_read.clear()
	for page in output_pages: page.queue_free()
	output_pages.clear()
	if is_instance_valid(feeding_page): feeding_page.queue_free()
	feeding_page = null
	output_geometry.clear()
	event_state = "idle"
	feed_progress = 0.0
	_dispatching_completion = false

func _kill_feed_tween() -> void:
	if _feed_tween != null and _feed_tween.is_valid(): _feed_tween.kill()


func restore_history(events: Array) -> int:
	if not continuous_output: return 0
	var restored := 0
	for value: Variant in events:
		if not value is Dictionary: continue
		var record: Dictionary = value
		var id := str(record.get("instance_id", "")).strip_edges()
		if id.is_empty() or not bool(record.get("acknowledged", false)) or received_event_ids.has(id): continue
		if not record.get("title") is String or not record.get("narrative") is String: continue
		var launch: Dictionary = _measure_output.call(record)
		var page: Control = OutputPage.new()
		page.name = "OutputPage" + str(output_pages.size())
		_host.add_child(page)
		# Restored history stays behind a live sheet that is still leaving the outlet.
		_host.move_child(page, output_pages.size())
		page.configure(record, _page_theme)
		page.set_meta("attachment_positions", launch.attachments)
		page.set_attachment_start(116.0 if not (launch.attachments as Dictionary).is_empty() else 0.0)
		page.set_feed_geometry(launch.size, 1.0)
		page.rotation = float(launch.angle)
		page.position = launch.origin - Vector2(0, (launch.size as Vector2).y).rotated(float(launch.angle)) + (launch.drift as Vector2)
		page.finish_output(output_pages.size())
		output_pages.append(page)
		received_event_ids[id] = true
		if id not in read_event_ids: read_event_ids.append(id)
		last_read = record.duplicate(true)
		restored += 1
	if restored > 0: pages_changed.emit()
	return restored


func _begin_physical_output() -> void:
	output_geometry = _measure_output.call(active_event)
	feeding_page = OutputPage.new()
	feeding_page.name = "OutputPage" + str(output_pages.size())
	_host.add_child(feeding_page)
	feeding_page.configure(active_event, _page_theme)
	feeding_page.set_meta("attachment_positions", output_geometry.attachments)
	feeding_page.set_attachment_start(116.0 if not (output_geometry.attachments as Dictionary).is_empty() else 0.0)
	sync_current_page()
	pages_changed.emit()
	output_started.emit(active_event.duplicate(true), feeding_page)


func sync_current_page() -> void:
	if not is_instance_valid(feeding_page) or output_geometry.is_empty(): return
	var dimensions: Vector2 = output_geometry.size
	feeding_page.set_feed_geometry(dimensions, feed_progress)
	feeding_page.rotation = float(output_geometry.angle)
	# Emission angle and feed speed are chosen at the outlet, never at the pile.
	feeding_page.position = output_geometry.origin - Vector2(0, dimensions.y * feed_progress).rotated(float(output_geometry.angle)) + (output_geometry.drift as Vector2) * feed_progress


func _local_page_bounds(page: Control) -> Rect2:
	var transform := page.get_transform()
	var corners := [transform * Vector2.ZERO, transform * Vector2(page.size.x,0), transform * page.size, transform * Vector2(0,page.size.y)]
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for corner: Vector2 in corners: bounds = bounds.expand(corner)
	return bounds


func inspection(stack_area: Rect2) -> Array[Dictionary]:
	var pages: Array[Dictionary] = []
	for page in output_pages:
		pages.append({"instance_id":str(page.event.get("instance_id", "")),"event":page.event.duplicate(true),
			"position":page.position,"size":page.size,"rotation":page.rotation,"bounds":_local_page_bounds(page),"stack_area":stack_area,"node_id":page.get_instance_id(),"tab_rect":page.history_tab_rect(),"tab_polygon":StationView.global_polygon(page,page.history_tab_rect()),
			"rect":page.get_global_rect(),"polygon":StationView.global_polygon(page,Rect2(Vector2.ZERO,page.size)),"visible":page.visible})
	return pages


func page_for_event(instance_id: String) -> Control:
	if is_instance_valid(feeding_page) and str(feeding_page.event.get("instance_id", "")) == instance_id: return feeding_page
	for page: Control in output_pages:
		if str(page.event.get("instance_id", "")) == instance_id: return page
	return null

func select_history_page(instance_id: String) -> void:
	for page: Control in output_pages:
		page.z_index = 1 if str(page.event.get("instance_id", "")) == instance_id else 0
	var selected := page_for_event(instance_id)
	# GUI input follows sibling order, so selection changes both orders together.
	if selected != null: _host.move_child(selected, _host.get_child_count() - 1)

func refresh_page_content() -> void:
	for page: Control in all_pages(): page.configure(page.event, page.theme)
