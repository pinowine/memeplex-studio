shader_type canvas_item;
render_mode unshaded;

uniform vec2 source_center_uv = vec2(0.5);
uniform bool solar_band = false;
uniform float daylight_fraction = 0.5;
varying vec4 ink_tint;

void vertex() {
	ink_tint = COLOR;
}

void fragment() {
	vec2 source_uv = UV;
	if (solar_band) {
		vec2 offset = UV - source_center_uv;
		float radius = length(offset);
		float angle = atan(offset.y, offset.x);
		float phi = mod(angle + 1.570796327 + 3.141592654, 6.283185307) - 3.141592654;
		float daylight = clamp(daylight_fraction, 0.0, 1.0);
		if (daylight >= 0.999999) {
			phi *= 0.5;
		} else if (daylight <= 0.000001) {
			phi = sign(phi) * 1.570796327 + phi * 0.5;
		} else if (abs(phi) <= 3.141592654 * daylight) {
			phi /= 2.0 * daylight;
		} else {
			phi = sign(phi) * 1.570796327 + (phi - sign(phi) * 3.141592654 * daylight) / (2.0 * (1.0 - daylight));
		}
		source_uv = source_center_uv + radius * vec2(cos(phi - 1.570796327), sin(phi - 1.570796327));
	}
	COLOR = texture(TEXTURE, source_uv) * ink_tint;
}
