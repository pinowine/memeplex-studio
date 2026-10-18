shader_type canvas_item;
render_mode unshaded;

uniform float pencil_variation : hint_range(0.0, 0.2) = 0.045;
uniform float grain_scale = 0.72;
varying vec2 pencil_position;

void vertex() {
	pencil_position = VERTEX;
}

void fragment() {
	vec4 source = COLOR;
	float paper = sin(pencil_position.x * grain_scale) * sin(pencil_position.y * grain_scale * 0.83);
	source.rgb *= 1.0 - pencil_variation * (0.5 + 0.5 * paper);
	COLOR = source;
}
