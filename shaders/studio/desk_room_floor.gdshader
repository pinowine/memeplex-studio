shader_type canvas_item;
render_mode unshaded;

uniform vec2 surface_size = vec2(9600.0, 6900.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = UV * surface_size;
	vec2 tile = floor(p / vec2(286.0, 286.0));
	vec2 edge = min(mod(p, 286.0), 286.0 - mod(p, 286.0));
	float seam = 1.0 - smoothstep(0.5, 2.6, min(edge.x, edge.y));
	float fine = hash(floor(p * 1.3));
	float patch = hash(tile) - 0.5;
	float rubbed = sin(p.x * 0.008 + sin(p.y * 0.004)) * 0.008;
	vec3 base = vec3(0.275, 0.284, 0.248) + patch * 0.018 + (fine - 0.5) * 0.027 + rubbed;
	COLOR = vec4(base * (1.0 - seam * 0.28), 1.0);
}
