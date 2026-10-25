shader_type canvas_item;
render_mode unshaded;

uniform vec2 surface_size = vec2(4800.0, 2700.0);
uniform float world_tile_size = 384.0;

void fragment() {
	// Mirror the tile at each seam while keeping grain fixed in desk space.
	vec2 uv = UV * surface_size / world_tile_size;
	vec2 mirrored = 1.0 - abs(fract(uv * 0.5) * 2.0 - 1.0);
	vec3 wood = texture(TEXTURE, mirrored).rgb;
	float luminance = dot(wood, vec3(0.299, 0.587, 0.114));
	wood = mix(wood, vec3(luminance), 0.54);
	wood = mix(wood, vec3(0.55, 0.51, 0.42), 0.22);
	COLOR = vec4(wood, 1.0);
}
