shader_type canvas_item;
render_mode unshaded;

uniform vec2 canvas_size = vec2(1.0);
uniform vec4 core = vec4(.5,.5,22.0,1.0);
uniform vec4 module_0;
uniform vec4 module_1;
uniform vec4 module_2;
uniform vec4 module_3;
uniform vec4 module_4;
uniform float membrane_blend = 14.0;
uniform vec4 ink : source_color = vec4(.28,.32,.25,.62);
varying vec2 paper_position;
varying vec4 vertex_tint;

void vertex() {
	paper_position = VERTEX;
	vertex_tint = COLOR;
}

float cell_distance(vec2 point, vec4 cell) {
	return length(point-cell.xy*canvas_size)-cell.z;
}

float merge_cell(float distance, vec2 point, vec4 cell) {
	if (cell.w < .5) return distance;
	float other = cell_distance(point,cell);
	float h = clamp(.5+.5*(other-distance)/membrane_blend,0.0,1.0);
	return mix(other,distance,h)-membrane_blend*h*(1.0-h);
}

void fragment() {
	vec2 point = UV*canvas_size;
	float distance = cell_distance(point,core);
	distance = merge_cell(distance,point,module_0);
	distance = merge_cell(distance,point,module_1);
	distance = merge_cell(distance,point,module_2);
	distance = merge_cell(distance,point,module_3);
	distance = merge_cell(distance,point,module_4);
	float line = 1.0-smoothstep(.25,1.15,abs(distance));
	float interior = 1.0-smoothstep(-.5,.5,distance);
	float pencil = .97+.03*sin(paper_position.x*1.23)*sin(paper_position.y*.79);
	COLOR = vec4(ink.rgb*pencil,ink.a*line+.018*interior)*vertex_tint;
}
