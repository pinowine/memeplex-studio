shader_type canvas_item;
render_mode unshaded;
uniform vec4 ink : source_color = vec4(.18,.21,.17,1.0);
uniform float opacity = .82;
uniform float pixel_scale = 2.0;
varying vec4 tint;
void vertex(){ tint=COLOR; }
void fragment(){
	float cover=texture(TEXTURE,UV).a;
	vec2 p=UV/ TEXTURE_PIXEL_SIZE / pixel_scale;
	float fibre=sin(p.x*2.43+p.y*.89)*sin(p.y*3.07-p.x*.21);
	float pore=smoothstep(.69,.88,fibre)*.22;
	COLOR=vec4(ink.rgb*tint.rgb,cover*opacity*(1.0-pore)*tint.a);
}
