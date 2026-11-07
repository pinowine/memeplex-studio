shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec4 focus_rect;
uniform vec4 source_rect;
uniform float blur_level : hint_range(0.0, 5.0) = 2.5;

float rect_distance(vec2 point, vec4 rect) {
	vec2 delta = abs(point - (rect.xy + rect.zw * 0.5)) - rect.zw * 0.5 - vec2(8.0);
	return length(max(delta, vec2(0.0))) + min(max(delta.x, delta.y), 0.0);
}

void fragment() {
	vec2 point = SCREEN_UV * viewport_size;
	float distance = rect_distance(point, focus_rect);
	if (source_rect.z > 0.0 && source_rect.w > 0.0) {
		distance = min(distance, rect_distance(point, source_rect));
	}
	float outside = smoothstep(0.0, 22.0, distance);
	float halo = (1.0 - smoothstep(0.0, 7.0, abs(distance - 2.0))) * 0.24;
	vec3 sharp = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, blur_level).rgb;
	vec3 backdrop = mix(sharp, blurred * 0.58, outside);
	COLOR = vec4(mix(backdrop, vec3(1.0, 0.84, 0.43), halo), 1.0);
}
