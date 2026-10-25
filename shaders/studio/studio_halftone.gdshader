shader_type canvas_item;
render_mode unshaded;
uniform sampler2D rendered_scene : hint_screen_texture, repeat_disable, filter_nearest;
uniform float pitch : hint_range(3.0, 16.0) = 5.5;
uniform float strength : hint_range(0.0, 1.0) = 0.22;
uniform vec3 paper_color : source_color = vec3(0.98, 0.96, 0.90);

float screen_dot(vec2 pixel, float angle, float coverage) {
	float c = cos(angle), s = sin(angle);
	vec2 rotated = vec2(c*pixel.x - s*pixel.y, s*pixel.x + c*pixel.y);
	vec2 cell = fract(rotated / pitch) - 0.5;
	float radius = sqrt(clamp(coverage, 0.0, 1.0)) * 0.70;
	float d = length(cell);
	float aa = max(fwidth(d), 0.025);
	return smoothstep(0.001, 0.016, coverage) * (1.0 - smoothstep(radius - aa, radius + aa, d));
}

void fragment() {
	vec3 photo = clamp(texture(rendered_scene, SCREEN_UV).rgb, vec3(0.0), vec3(1.0));
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	float k = 1.0 - max(photo.r, max(photo.g, photo.b));
	vec3 chroma = (vec3(1.0) - photo - vec3(k)) / max(1.0-k, 0.001);
	float cyan = screen_dot(pixel, 0.261799, chroma.r);
	float magenta = screen_dot(pixel + vec2(1.2, 0.4), 1.308997, chroma.g);
	float yellow = screen_dot(pixel, 0.0, chroma.b);
	float black = screen_dot(pixel, 0.785398, k);
	vec3 print_color = paper_color * vec3(1.0-cyan*.90, 1.0-magenta*.90, 1.0-yellow*.88) * (1.0-black*.91);
	COLOR = vec4(mix(photo, print_color, strength), 1.0);
}
