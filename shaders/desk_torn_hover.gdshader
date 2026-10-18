shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform vec2 object_size = vec2(256.0);
uniform vec2 rect_origin = vec2(12.0);
uniform vec2 padding = vec2(12.0);
uniform bool geometry_is_padded = true;
uniform vec4 source_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool source_flip_h = false;
uniform bool source_flip_v = false;
uniform float band_width : hint_range(1.0, 32.0) = 8.0;
uniform float alpha_cutoff : hint_range(0.0, 0.5) = 0.02;
uniform vec4 outline_color : source_color = vec4(0.91, 0.76, 0.38, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.78;
uniform float dot_pitch : hint_range(1.0, 16.0) = 4.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;

varying vec2 local_pixel;
varying vec4 item_modulate;

float alpha_at(vec2 pixel) {
	vec2 uv = pixel / max(object_size, vec2(1.0));
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) { return 0.0; }
	if (source_flip_h) { uv.x = 1.0 - uv.x; }
	if (source_flip_v) { uv.y = 1.0 - uv.y; }
	return texture(source_texture, source_uv_rect.xy + uv * source_uv_rect.zw).a;
}

float hash_at(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	if (!geometry_is_padded) {
		vec2 direction = step(object_size * 0.5, VERTEX - rect_origin) * 2.0 - 1.0;
		VERTEX += direction * padding;
	}
	local_pixel = VERTEX - rect_origin;
	item_modulate = COLOR;
}

void fragment() {
	float core = alpha_at(local_pixel);
	float width = max(band_width, 1.0);
	float expanded = 0.0;
	for (int ring = 1; ring <= 2; ring++) {
		for (int sample_index = 0; sample_index < 12; sample_index++) {
			float angle = float(sample_index) * TAU / 12.0;
			vec2 offset = vec2(cos(angle), sin(angle)) * width * float(ring) * 0.5;
			expanded = max(expanded, alpha_at(local_pixel + offset));
		}
	}
	float rag = hash_at(floor(local_pixel / 2.8));
	float tear = mix(1.0, smoothstep(0.10, 0.36, rag), roughness);
	vec2 dot_cell = fract(local_pixel / max(dot_pitch, 1.0)) - vec2(0.5);
	float dot_distance = length(dot_cell);
	float dot_edge = max(fwidth(dot_distance), 0.01);
	float dots = 1.0 - smoothstep(0.27 - dot_edge, 0.27 + dot_edge, dot_distance);
	// Never cover a visible source pixel, including semi-transparent paper edges.
	float outside = 1.0 - step(max(alpha_cutoff, 0.00001), core);
	float alpha = expanded * outside * tear * mix(0.34, 1.0, dots) * opacity;
	COLOR = vec4(outline_color.rgb * item_modulate.rgb, alpha * outline_color.a * item_modulate.a);
}
