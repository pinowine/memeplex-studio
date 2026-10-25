shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec4 sample_colour = texture(TEXTURE, UV);
	float value = max(sample_colour.r, max(sample_colour.g, sample_colour.b));
	COLOR = vec4(sample_colour.rgb, sample_colour.a * smoothstep(0.015, 0.075, value));
}
