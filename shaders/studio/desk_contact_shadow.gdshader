shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D source_texture : filter_linear, repeat_disable;

uniform vec2 object_size = vec2(256.0);
uniform vec2 rect_origin = vec2(0.0);
uniform vec2 padding = vec2(24.0);
uniform bool geometry_is_padded = false;
uniform vec2 shadow_offset = vec2(7.0, 10.0);
uniform float shadow_blur : hint_range(0.0, 128.0) = 10.0;
uniform float shadow_opacity : hint_range(0.0, 1.0) = 0.28;
uniform float ao_radius : hint_range(0.0, 128.0) = 3.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.2;
uniform vec4 shadow_color : source_color = vec4(0.08, 0.07, 0.06, 1.0);
uniform vec4 source_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool source_flip_h = false;
uniform bool source_flip_v = false;

varying vec2 local_pixel;
varying vec4 item_modulate;

float source_alpha(vec2 pixel) {
	vec2 uv = pixel / max(object_size, vec2(1.0));
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	if (source_flip_h) { uv.x = 1.0 - uv.x; }
	if (source_flip_v) { uv.y = 1.0 - uv.y; }
	return texture(source_texture, source_uv_rect.xy + uv * source_uv_rect.zw).a;
}

float soft_alpha(vec2 pixel, float radius) {
	// A normalized two-ring kernel keeps the support inside the configured padding.
	float value = source_alpha(pixel) * 0.2;
	value += source_alpha(pixel + vec2(radius * 0.5, 0.0)) * 0.1;
	value += source_alpha(pixel - vec2(radius * 0.5, 0.0)) * 0.1;
	value += source_alpha(pixel + vec2(0.0, radius * 0.5)) * 0.1;
	value += source_alpha(pixel - vec2(0.0, radius * 0.5)) * 0.1;
	value += source_alpha(pixel + vec2(radius, 0.0)) * 0.05;
	value += source_alpha(pixel - vec2(radius, 0.0)) * 0.05;
	value += source_alpha(pixel + vec2(0.0, radius)) * 0.05;
	value += source_alpha(pixel - vec2(0.0, radius)) * 0.05;
	vec2 diagonal = vec2(radius * 0.70710678);
	value += source_alpha(pixel + diagonal) * 0.05;
	value += source_alpha(pixel - diagonal) * 0.05;
	value += source_alpha(pixel + vec2(diagonal.x, -diagonal.y)) * 0.05;
	value += source_alpha(pixel + vec2(-diagonal.x, diagonal.y)) * 0.05;
	return value;
}

void vertex() {
	vec2 direction = step(object_size * 0.5, VERTEX - rect_origin) * 2.0 - 1.0;
	if (!geometry_is_padded) { VERTEX += direction * padding; }
	local_pixel = VERTEX - rect_origin;
	item_modulate = COLOR;
}

void fragment() {
	float cast = soft_alpha(local_pixel - shadow_offset, shadow_blur) * shadow_opacity;
	float contact = soft_alpha(local_pixel, ao_radius) * ao_strength;
	float alpha = 1.0 - (1.0 - clamp(cast, 0.0, 1.0)) * (1.0 - clamp(contact, 0.0, 1.0));
	COLOR = vec4(shadow_color.rgb * item_modulate.rgb, alpha * shadow_color.a * item_modulate.a);
}
