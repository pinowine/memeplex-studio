shader_type canvas_item;
render_mode unshaded;

uniform float eye_height = 0.064;
uniform float pupil_x = 0.018;
uniform float brow_tilt = 0.0;
uniform float brow_raise = 0.0;
uniform float closed_eye = 0.0;
uniform float smile = 0.0;
uniform float mouth_open = 0.0;
uniform float mouth_width = 0.095;
uniform float blink = 0.0;

varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

float ellipse_coverage(vec2 point, vec2 center, vec2 radius) {
	float distance = length((point - center) / radius);
	float edge = fwidth(distance) * 0.5;
	return 1.0 - smoothstep(1.0 - edge, 1.0 + edge, distance);
}

float box_coverage(vec2 point, vec2 minimum, vec2 maximum) {
	vec2 edge = fwidth(point) * 0.5;
	vec2 mask = smoothstep(minimum - edge, minimum + edge, point) * (1.0 - smoothstep(maximum - edge, maximum + edge, point));
	return mask.x * mask.y;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 ink = texture(TEXTURE, vec2(0.175, 0.465)).rgb;
	vec3 paper = texture(TEXTURE, vec2(0.735, 0.795)).rgb;
	float eye_patch = box_coverage(UV, vec2(0.245, 0.365), vec2(0.490, 0.577));
	source.rgb = mix(source.rgb, ink, eye_patch);
	float closure = max(closed_eye, blink);
	float eye = ellipse_coverage(UV, vec2(0.365, 0.480), vec2(0.095, eye_height * (1.0 - blink * 0.8)));
	float pupil = ellipse_coverage(UV, vec2(0.365 + pupil_x, 0.480), vec2(0.031, eye_height * 0.78));
	float x = (UV.x - 0.365) / 0.095;
	float arch = 0.490 - 0.026 * (1.0 - x * x);
	float lid_end = 1.0 - smoothstep(1.0 - fwidth(x) * 0.5, 1.0 + fwidth(x) * 0.5, abs(x));
	float lid = (1.0 - smoothstep(0.008 - fwidth(UV.y) * 0.5, 0.008 + fwidth(UV.y) * 0.5, abs(UV.y - arch))) * lid_end;
	eye = mix(eye * (1.0 - pupil), lid, closure);
	float brow_y = 0.398 - brow_raise + (UV.x - 0.365) * brow_tilt * 3.5;
	float brow = (1.0 - smoothstep(0.010 - fwidth(UV.y) * 0.5, 0.010 + fwidth(UV.y) * 0.5, abs(UV.y - brow_y))) * box_coverage(UV, vec2(0.274, 0.340), vec2(0.458, 0.442));
	source.rgb = mix(source.rgb, paper, max(eye, brow));
	float mouth_patch = box_coverage(UV, vec2(0.390, 0.716), vec2(0.680, 0.810));
	source.rgb = mix(source.rgb, paper, mouth_patch);
	float mouth_x = (UV.x - 0.535) / mouth_width;
	float mouth_y = 0.751 + smile * (1.0 - mouth_x * mouth_x);
	float mouth_end = 1.0 - smoothstep(1.0 - fwidth(mouth_x) * 0.5, 1.0 + fwidth(mouth_x) * 0.5, abs(mouth_x));
	float mouth = (1.0 - smoothstep(0.010 + mouth_open - fwidth(UV.y) * 0.5, 0.010 + mouth_open + fwidth(UV.y) * 0.5, abs(UV.y - mouth_y))) * mouth_end;
	source.rgb = mix(source.rgb, ink, mouth);
	COLOR = source * item_modulate;
}
