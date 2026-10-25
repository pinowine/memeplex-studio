shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec2 bounds_min = vec2(0.0);
uniform vec2 bounds_size = vec2(1.0);
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float press_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 hover_color : source_color = vec4(1.0, 0.78, 0.30, 1.0);
uniform vec4 press_color : source_color = vec4(1.0, 0.48, 0.12, 1.0);
varying vec2 button_position;

void vertex() {
	button_position = (VERTEX.xz - bounds_min) / bounds_size;
	VERTEX += NORMAL * 0.00008;
}

void fragment() {
	vec2 distances = min(button_position, vec2(1.0) - button_position);
	float edge = 1.0 - smoothstep(0.055, 0.15, min(distances.x, distances.y));
	float amount = max(hover_amount, press_amount);
	ALBEDO = mix(hover_color.rgb, press_color.rgb, press_amount);
	ALPHA = amount * mix(0.10 + press_amount * 0.15, 0.78 + press_amount * 0.12, edge);
}
