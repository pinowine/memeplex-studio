shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;

uniform sampler2D desktop_texture : filter_linear, repeat_disable;
uniform bool paper_stock_enabled = false;
uniform sampler2D paper_stock_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D paper_stock_roughness : filter_linear_mipmap, repeat_disable;
uniform vec2 source_size = vec2(1600.0, 900.0);
uniform bool world_mapping = false;
uniform vec2 origin_px = vec2(0.0);
uniform vec2 u_px = vec2(1600.0, 0.0);
uniform vec2 v_px = vec2(0.0, 900.0);
uniform vec2 canvas_origin = vec2(0.0);
uniform vec2 canvas_x = vec2(1.0, 0.0);
uniform vec2 canvas_y = vec2(0.0, 1.0);
uniform vec4 background : source_color = vec4(0.0);
uniform float screen_emission = 0.08;
uniform bool remove_hardware = false;
uniform int feed_curve = 0;
uniform float sheet_depth_m = 0.33;
uniform float mouth_height_m = 0.13;
uniform vec4 equipment_rects[4];
uniform float equipment_angles[4];
varying vec2 logical_pixel;

void vertex() {
	if (feed_curve != 0) {
		float distance_from_mouth = (feed_curve == 1 ? UV.y : 1.0-UV.y) * sheet_depth_m;
		VERTEX.y += mouth_height_m * exp(-distance_from_mouth / 0.032);
	}
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	logical_pixel = world.xz * 1000.0 + vec2(800.0, 450.0);
}

void fragment() {
	vec2 sample_pixel = origin_px + UV.x * u_px + UV.y * v_px;
	if (world_mapping) {
		sample_pixel = canvas_origin + canvas_x * logical_pixel.x + canvas_y * logical_pixel.y;
	}
	if (remove_hardware) {
		for (int i = 0; i < 4; i++) {
			vec2 delta = logical_pixel - equipment_rects[i].xy;
			float a = equipment_angles[i];
			vec2 local = vec2(cos(a)*delta.x + sin(a)*delta.y, -sin(a)*delta.x + cos(a)*delta.y);
			if (all(lessThan(abs(local), equipment_rects[i].zw * 0.5))) { discard; }
		}
		if (distance(logical_pixel, vec2(463.0, 114.0)) < 108.0) { discard; }
	}
	vec2 uv = sample_pixel / source_size;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { discard; }
	vec4 ink = texture(desktop_texture, uv);
	// Transparent viewport attachments contain premultiplied RGB.
	vec3 rgb = ink.rgb / max(ink.a, 0.0001);
	// The retained non-HDR 2D viewport is sRGB; 3D lighting operates in linear RGB.
	rgb = mix(rgb/12.92, pow((rgb+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),rgb));
	float alpha = ink.a + background.a * (1.0 - ink.a);
	rgb = mix(background.rgb, rgb, ink.a / max(alpha, 0.0001));
	ALBEDO = clamp(rgb, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.91;
	if (paper_stock_enabled) {
		// UV is live content; UV2 retains the independent Painter atlas coordinates.
		vec4 stock = texture(paper_stock_texture, UV2);
		ALBEDO *= stock.rgb;
		ROUGHNESS = texture(paper_stock_roughness, UV2).r;
		// Stock can mask the live ink, but must not fill its transparent paper outline.
		alpha *= stock.a;
	}
	EMISSION = ALBEDO * screen_emission;
	ALPHA = alpha;
}
