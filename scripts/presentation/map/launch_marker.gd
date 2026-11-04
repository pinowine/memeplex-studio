extends BaseButton

signal confirmed

const INK := Color(0.18, 0.20, 0.15)
const PAPER := Color(1.0, 0.96, 0.80)
const CENTER := Vector2(34, 31)
const TIP := Vector2(34, 81)
const HOVER_RESPONSE := 9.0
const BREATH_PERIOD := 2.6

var popping := false
var _burst := 0.0
var _animation: Tween
var _hover_amount := 0.0
var _breath_time := 0.0

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pressed.connect(pop)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var target := 1.0 if not disabled and (is_hovered() or has_focus()) else 0.0
	if target == 0.0 and _hover_amount < 0.001:
		if _hover_amount > 0.0:
			_hover_amount = 0.0
			queue_redraw()
		return
	_hover_amount = lerpf(_hover_amount, target, 1.0 - exp(-HOVER_RESPONSE * delta))
	_breath_time += delta
	queue_redraw()

func reset() -> void:
	if _animation != null and _animation.is_valid(): _animation.kill()
	popping = false
	disabled = false
	_burst = 0.0
	_hover_amount = 0.0
	_breath_time = 0.0
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
		var breath := sin(_breath_time * TAU / BREATH_PERIOD)
		var hover_scale := 1.0 + _hover_amount * (0.018 + breath * 0.008)
		var expansion := 1.0 + _burst * 0.5
		# Keep the tail anchored as the bubble breathes.
		var origin := TIP * (1.0 - hover_scale) + CENTER * (1.0 - expansion) * hover_scale
		draw_set_transform(origin, 0.0, Vector2.ONE * expansion * hover_scale)
		var warmth := _hover_amount * (0.8 + breath * 0.2)
		var paper := PAPER.lerp(Color(1.0, 0.99, 0.90), warmth)
		var ink := INK.lerp(Color(0.25, 0.28, 0.19), warmth)
		var outline := PackedVector2Array([TIP])
		for i in 49:
			var angle := lerpf(2.55, TAU + 0.59, float(i) / 48.0)
			outline.append(CENTER + Vector2(cos(angle), sin(angle)) * 28.0)
		draw_colored_polygon(outline, ink)
		outline.append(TIP)
		draw_polyline(outline, paper, 2.0, true)
		draw_circle(CENTER, 21.0, paper)
		draw_arc(CENTER, 24.0, 0.0, TAU, 48, Color(paper, _hover_amount), 2.0, true)
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
