shader_type canvas_item;
render_mode unshaded;

uniform float blend_depth : hint_range(0.0, 1.0) = 0.1;
uniform sampler2D brain_atlas : filter_linear;

vec4 slice(float index, vec2 point) {
	vec2 cell = vec2(mod(index, 3.0), floor(index / 3.0));
	return texture(brain_atlas, (cell + clamp(point, vec2(0.002), vec2(0.998))) / vec2(3.0, 2.0));
}

void fragment() {
	float position = clamp(blend_depth * 5.0 - 0.5, 0.0, 4.0);
	vec4 brain = mix(slice(floor(position), UV), slice(min(4.0, floor(position) + 1.0), UV), fract(position));
	float grey = dot(brain.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(0.12, 0.13, 0.12), vec3(0.87, 0.85, 0.80), grey), smoothstep(0.018, 0.06, grey) * 0.90);
}
