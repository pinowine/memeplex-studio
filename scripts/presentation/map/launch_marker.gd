extends BaseButton

signal confirmed

const INK := Color(0.18, 0.20, 0.15)
const PAPER := Color(1.0, 0.96, 0.80)
const CENTER := Vector2(34, 31)
const TIP := Vector2(34, 81)

var popping := false
var _burst := 0.0
var _animation: Tween

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(pop)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func reset() -> void:
	if _animation != null and _animation.is_valid(): _animation.kill()
	popping = false
	disabled = false
	_burst = 0.0
	queue_redraw()

func pop() -> void:
	if disabled or popping or not is_visible_in_tree(): return
	popping = true
	disabled = true
	_animation = create_tween()
	_animation.tween_method(_set_burst, 0.0, 1.0, 0.30)
	_animation.tween_callback(func():
		hide()
		confirmed.emit())

func _set_burst(value: float) -> void:
	_burst = value
	queue_redraw()

func _draw() -> void:
	if _burst < 0.22:
		var expansion := 1.0 + _burst * 0.5
		draw_set_transform(CENTER * (1.0 - expansion), 0.0, Vector2.ONE * expansion)
		var outline := PackedVector2Array([TIP])
		for i in 49:
			var angle := lerpf(2.55, TAU + 0.59, float(i) / 48.0)
			outline.append(CENTER + Vector2(cos(angle), sin(angle)) * 28.0)
		draw_colored_polygon(outline, INK)
		outline.append(TIP)
		draw_polyline(outline, PAPER, 2.0, true)
		draw_circle(CENTER, 21.0, PAPER)
		if is_hovered() or has_focus(): draw_arc(CENTER, 24.0, 0.0, TAU, 48, PAPER, 2.0, true)
		_draw_check(1.0)
	else:
		var progress := inverse_lerp(0.22, 1.0, _burst)
		var fade := 1.0 - progress
		var radius := lerpf(29.0, 48.0, progress)
		for i in 8:
			var angle := TAU * float(i) / 8.0
			var direction := Vector2.from_angle(angle)
			draw_arc(CENTER, radius, angle - 0.14, angle + 0.14, 6, Color(PAPER, fade), 4.0, true)
			draw_line(CENTER + direction * (radius + 4.0), CENTER + direction * (radius + 10.0), Color(INK, fade), 2.0, true)
		_draw_check(fade)

func _draw_check(opacity: float) -> void:
	var check := PackedVector2Array([CENTER + Vector2(-11, 0), CENTER + Vector2(-3, 8), CENTER + Vector2(12, -9)])
	draw_polyline(check, Color(INK, opacity), 5.0, true)
