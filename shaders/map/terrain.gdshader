shader_type canvas_item;
render_mode unshaded;
uniform sampler2D elevation_field : filter_linear, repeat_disable;
uniform vec2 world_size;
uniform float detail_level = 0.0;
uniform vec4 contour_color : source_color = vec4(0.22, 0.28, 0.25, 0.10);
uniform float contour_interval = 0.06;
varying vec2 world_point;
void vertex() {
    world_point = VERTEX;
}
float smooth_height(vec2 uv) {
    vec2 q = uv * world_size - vec2(0.5);
    vec2 t = fract(q);
    vec2 i = floor(q);
    vec2 w0 = pow(vec2(1.0)-t, vec2(3.0))/6.0;
    vec2 w1 = (3.0*t*t*t-6.0*t*t+4.0)/6.0;
    vec2 w2 = (-3.0*t*t*t+3.0*t*t+3.0*t+1.0)/6.0;
    vec2 w3 = t*t*t/6.0;
    vec2 g0 = w0+w1;
    vec2 g1 = w2+w3;
    vec2 p0 = (i-1.0+w1/g0+0.5)/world_size;
    vec2 p1 = (i+1.0+w3/g1+0.5)/world_size;
    return texture(elevation_field,vec2(p0.x,p0.y)).r*g0.x*g0.y
        + texture(elevation_field,vec2(p1.x,p0.y)).r*g1.x*g0.y
        + texture(elevation_field,vec2(p0.x,p1.y)).r*g0.x*g1.y
        + texture(elevation_field,vec2(p1.x,p1.y)).r*g1.x*g1.y;
}
void fragment() {
    if (detail_level > 1.5) {
        vec2 uv = (world_point + vec2(0.5)) / world_size;
        float height = smooth_height(uv);
        float band = height / contour_interval;
        float distance_to_line = abs(fract(band + 0.5) - 0.5);
        float pixel_width = max(fwidth(band), 0.00001);
        float coverage = 1.0 - smoothstep(pixel_width * 0.2, pixel_width * 1.0, distance_to_line);
        COLOR.rgb = mix(COLOR.rgb, contour_color.rgb, coverage * contour_color.a);
    }
}
