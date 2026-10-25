shader_type canvas_item;
render_mode unshaded;

uniform vec2 light_position = vec2(180.0, 20.0);
uniform float light_height : hint_range(1.0, 1200.0) = 340.0;
uniform vec4 light_color : source_color = vec4(1.0, 0.96, 0.87, 1.0);
uniform float ambient : hint_range(0.0, 1.0) = 0.65;
uniform float roughness : hint_range(0.0, 1.0) = 0.78;
uniform float subsurface : hint_range(0.0, 1.0) = 0.06;
uniform float edge_height : hint_range(0.0, 24.0) = 5.0;
uniform vec4 source_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float dot_pitch : hint_range(1.0, 64.0) = 14.0;
uniform float ink_strength : hint_range(0.0, 1.0) = 0.28;
uniform vec4 ink_color : source_color = vec4(0.16, 0.20, 0.17, 1.0);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.08;
uniform float posterize_levels : hint_range(0.0, 16.0, 1.0) = 0.0;

varying vec2 canvas_position;
varying vec2 canvas_x;
varying vec2 canvas_y;
varying vec4 item_modulate;

float inside_source(vec2 uv) {
	vec2 lower = step(source_uv_rect.xy, uv);
	vec2 upper = step(uv, source_uv_rect.xy + source_uv_rect.zw);
	return lower.x * lower.y * upper.x * upper.y;
}

void vertex() {
	canvas_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	canvas_x = (MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xy;
	canvas_y = (MODEL_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
	item_modulate = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 dx = vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
	vec2 dy = vec2(0.0, TEXTURE_PIXEL_SIZE.y);
	float left = texture(TEXTURE, UV - dx).a * inside_source(UV - dx);
	float right = texture(TEXTURE, UV + dx).a * inside_source(UV + dx);
	float up = texture(TEXTURE, UV - dy).a * inside_source(UV - dy);
	float down = texture(TEXTURE, UV + dy).a * inside_source(UV + dy);
	vec2 slope = vec2(left - right, up - down) * edge_height;
	vec2 world_slope = normalize(canvas_x) * slope.x + normalize(canvas_y) * slope.y;
	vec3 normal = normalize(vec3(world_slope, 1.0));
	vec3 toward_light = normalize(vec3(light_position - canvas_position, max(light_height, 1.0)));
	float diffuse = max(dot(normal, toward_light), 0.0);
	float light_amount = ambient + (1.0 - ambient) * diffuse;
	float shininess = mix(96.0, 4.0, clamp(roughness, 0.0, 1.0));
	float specular = pow(max(reflect(-toward_light, normal).z, 0.0), shininess) * (1.0 - roughness) * 0.09;
	vec3 color = source.rgb;
	if (posterize_levels >= 2.0) {
		color = floor(color * posterize_levels + vec3(0.5)) / posterize_levels;
	}
	vec2 cell = fract((UV / TEXTURE_PIXEL_SIZE) / max(dot_pitch, 1.0)) - vec2(0.5);
	float dot_radius = mix(0.08, 0.46, clamp(1.0 - dot(source.rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0));
	float dot_distance = length(cell);
	float feather = max(fwidth(dot_distance), 0.005);
	float dots = 1.0 - smoothstep(dot_radius - feather, dot_radius + feather, dot_distance);
	color = mix(color, color * ink_color.rgb, clamp(tint_mix, 0.0, 1.0) * ink_color.a);
	color = mix(color, ink_color.rgb, dots * clamp(ink_strength, 0.0, 1.0) * ink_color.a);
	color *= mix(vec3(1.0), light_color.rgb, light_color.a) * light_amount;
	color += light_color.rgb * specular * light_color.a;
	color += source.rgb * (1.0 - diffuse) * subsurface * 0.08;
	// Lighting affects color only; shadows still read the pristine source alpha.
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)) * item_modulate.rgb, source.a * item_modulate.a);
}
