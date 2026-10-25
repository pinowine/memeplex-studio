shader_type canvas_item;
render_mode unshaded;

uniform vec3 inverse_x;
uniform vec3 inverse_y;
uniform vec3 inverse_w;
uniform vec2 display_size;

void fragment() {
	vec3 screen = vec3(UV * display_size, 1.0);
	float denominator = dot(inverse_w, screen);
	vec2 plane = vec2(dot(inverse_x, screen), dot(inverse_y, screen)) / denominator;
	if (abs(denominator) < 0.000001 || any(lessThan(plane, vec2(0.0))) || any(greaterThan(plane, vec2(1.0)))) {
		COLOR = vec4(0.0);
	} else {
		COLOR = texture(TEXTURE, plane);
	}
}
