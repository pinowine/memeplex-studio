shader_type canvas_item;
render_mode unshaded;

uniform vec2 paper_size = vec2(1140.0, 740.0);
uniform sampler2D macro_map : source_color, filter_linear_mipmap, repeat_disable;
uniform float fiber_seed = 0.0;
uniform float detail_density : hint_range(3.0, 6.0) = 3.2;
uniform float fiber_strength : hint_range(0.0, 0.1) = 0.022;
uniform float grain_strength : hint_range(0.0, 0.1) = 0.012;
uniform bool sharpen_alpha = false;
uniform bool painter_stock_only = false;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

float paper_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33 + fiber_seed);
	return fract((q.x + q.y) * q.z);
}

float paper_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 u = fract(p);
	u = u * u * (3.0 - 2.0 * u);
	float a = paper_hash(cell);
	float b = paper_hash(cell + vec2(1.0, 0.0));
	float c = paper_hash(cell + vec2(0.0, 1.0));
	float d = paper_hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float filtered_noise(vec2 point) {
	// Fade subpixel fibres instead of letting a moving camera produce moire.
	float footprint = max(length(dFdx(point)), length(dFdy(point)));
	float contrast = 1.0 - smoothstep(0.55, 2.4, footprint);
	return (paper_noise(point) - 0.5) * contrast;
}

void fragment() {
	vec4 source_paper = texture(TEXTURE, UV);
	vec2 world = UV * max(paper_size, vec2(1.0));
	vec3 macro = texture(macro_map, UV).rgb;
	float outside_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float fold_weight = 0.72 * (1.0 - smoothstep(0.018, 0.14, outside_distance));
	vec3 paper = mix(macro, source_paper.rgb, fold_weight);
	float cloud = filtered_noise(world * 0.031) * 0.018;
	float long_fibres = filtered_noise(world * vec2(0.23, detail_density));
	vec2 diagonal = vec2(world.x * 0.86 + world.y * 0.51, -world.x * 0.51 + world.y * 0.86);
	float crossed_fibres = filtered_noise(diagonal * vec2(0.18, detail_density * 0.83));
	float grain = filtered_noise(world * detail_density);
	paper += vec3(cloud + (long_fibres + crossed_fibres) * fiber_strength + grain * grain_strength);
	float alpha = source_paper.a;
	if (sharpen_alpha) {
		// The 0.5 contour stays in place; this option changes the translucent fringe.
		float width = max(fwidth(alpha) * 0.5, 0.001);
		alpha = smoothstep(0.5 - width, 0.5 + width, alpha);
	}
	if (painter_stock_only) {
		COLOR = vec4(vec3(1.0), alpha * item_tint.a);
	} else {
		COLOR = vec4(clamp(paper, vec3(0.0), vec3(1.0)), alpha) * item_tint;
	}
}
