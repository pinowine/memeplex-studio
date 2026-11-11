@tool
extends TextureRect

const EXPRESSION_SHADER := preload("res://shaders/ui/mentor_portrait.gdshader")
const EXPRESSIONS := {
	"neutral": {},
	"friendly": {"eye_height":0.064, "pupil_x":0.018, "brow_tilt":-0.015, "brow_raise":0.010, "closed_eye":false, "smile":0.040, "mouth_open":0.006, "mouth_width":0.115},
	"confused": {"eye_height":0.086, "pupil_x":-0.015, "brow_tilt":-0.065, "brow_raise":0.014, "closed_eye":false, "smile":-0.010, "mouth_open":0.026, "mouth_width":0.036},
	"confident": {"eye_height":0.033, "pupil_x":0.026, "brow_tilt":0.035, "brow_raise":0.000, "closed_eye":false, "smile":0.024, "mouth_open":0.005, "mouth_width":0.105},
	"thinking": {"eye_height":0.043, "pupil_x":-0.026, "brow_tilt":-0.025, "brow_raise":0.006, "closed_eye":false, "smile":0.000, "mouth_open":0.004, "mouth_width":0.070},
	"curious": {"eye_height":0.078, "pupil_x":0.029, "brow_tilt":-0.030, "brow_raise":0.020, "closed_eye":false, "smile":0.010, "mouth_open":0.013, "mouth_width":0.065},
	"concerned": {"eye_height":0.041, "pupil_x":0.004, "brow_tilt":0.065, "brow_raise":0.004, "closed_eye":false, "smile":-0.031, "mouth_open":0.005, "mouth_width":0.095},
	"pleased": {"eye_height":0.020, "pupil_x":0.012, "brow_tilt":-0.012, "brow_raise":0.014, "closed_eye":true, "smile":0.045, "mouth_open":0.009, "mouth_width":0.115},
	"excited": {"eye_height":0.086, "pupil_x":0.015, "brow_tilt":-0.012, "brow_raise":0.025, "closed_eye":false, "smile":0.032, "mouth_open":0.031, "mouth_width":0.100}
}
const HOVER_EMOTIONS := {
	"LOC_OPENING_HOVER_FINE":"pleased",
	"LOC_OPENING_HOVER_PEAK":"curious",
	"LOC_OPENING_HOVER_67":"confident",
	"LOC_OPENING_HOVER_IDEOLOGY":"confident",
	"LOC_OPENING_HOVER_PRAGMATICS":"thinking"
}

var _emotion := "neutral"
var _expression_material: ShaderMaterial
var _pose_tween: Tween

func _ready() -> void:
	_expression_material = ShaderMaterial.new()
	_expression_material.shader = EXPRESSION_SHADER
	material = _expression_material
	resized.connect(func(): pivot_offset = size * 0.5)
	pivot_offset = size * 0.5

static func emotion_for(step: Dictionary, text_key: String) -> String:
	return str(HOVER_EMOTIONS.get(text_key, step.get("emotion", "neutral")))

func set_emotion(value: String) -> void:
	var next_emotion: String = {"rotate":"confused", "pulse":"excited", "":"neutral"}.get(value, value)
	if next_emotion == _emotion: return
	_emotion = next_emotion
	_expression_material.set_shader_parameter("expression_active", _emotion != "neutral")
	for key: String in EXPRESSIONS[_emotion]:
		_expression_material.set_shader_parameter(key, EXPRESSIONS[_emotion][key])
	if _pose_tween != null and _pose_tween.is_valid(): _pose_tween.kill()
	_pose_tween = create_tween().set_parallel()
	var tilt: float = {"neutral":0.0, "friendly":-0.04, "confused":-0.13, "confident":-0.035, "thinking":0.075, "curious":-0.08, "concerned":0.035, "pleased":0.0, "excited":0.045}[_emotion]
	var lift: float = {"neutral":1.0, "friendly":1.04, "confused":1.03, "confident":1.06, "thinking":1.0, "curious":1.06, "concerned":0.98, "pleased":1.08, "excited":1.14}[_emotion]
	_pose_tween.tween_property(self, "rotation", tilt, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pose_tween.tween_property(self, "scale", Vector2.ONE * lift, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pose_tween.chain().tween_property(self, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func inspection() -> Dictionary:
	return {"emotion":_emotion, "expression":EXPRESSIONS[_emotion].duplicate(), "available_emotions":EXPRESSIONS.keys(), "source_texture":texture.resource_path, "rotation":rotation, "scale":scale}
