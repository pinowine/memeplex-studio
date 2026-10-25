shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_disabled;
uniform sampler2D printed_ring : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 source_center_uv = vec2(0.5);
uniform float daylight_fraction = 0.5;

void fragment() {
	vec2 offset = UV-source_center_uv;
	float radius = length(offset);
	float phi = mod(atan(offset.y,offset.x)+1.570796327+3.141592654,6.283185307)-3.141592654;
	float daylight = clamp(daylight_fraction,0.0,1.0);
	if (daylight>=0.999999) { phi*=0.5; }
	else if (daylight<=0.000001) { phi=sign(phi)*1.570796327+phi*0.5; }
	else if (abs(phi)<=3.141592654*daylight) { phi/=2.0*daylight; }
	else { phi=sign(phi)*1.570796327+(phi-sign(phi)*3.141592654*daylight)/(2.0*(1.0-daylight)); }
	vec2 uv=source_center_uv+radius*vec2(cos(phi-1.570796327),sin(phi-1.570796327));
	vec4 ink=texture(printed_ring,uv);
	ALBEDO=ink.rgb;ALPHA=ink.a;
}
