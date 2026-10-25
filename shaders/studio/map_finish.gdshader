shader_type canvas_item;
render_mode unshaded;

uniform sampler2D map_image : hint_screen_texture, filter_linear;
uniform vec4 season_mix = vec4(0.25, 0.25, 0.25, 0.25);
uniform float paper_strength : hint_range(0.0, 0.05) = 0.008;
uniform float season_strength : hint_range(0.0, 1.0) = 0.22;
uniform vec3 spring_ink = vec3(0.980, 1.015, 0.970);
uniform vec3 summer_ink = vec3(1.025, 1.015, 0.970);
uniform vec3 autumn_ink = vec3(1.035, 0.990, 0.960);
uniform vec3 winter_ink = vec3(0.970, 0.995, 1.025);

float hash(vec2 point) {
    return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float paper_density(vec2 point) {
    vec2 cell = floor(point);
    vec2 weight = fract(point);
    weight = weight * weight * (3.0 - 2.0 * weight);
    return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), weight.x),
        mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), weight.x), weight.y);
}

void fragment() {
    vec4 map = texture(map_image, SCREEN_UV);
    vec3 ink = spring_ink * season_mix.x + summer_ink * season_mix.y
        + autumn_ink * season_mix.z + winter_ink * season_mix.w;
    float density = paper_density(FRAGCOORD.xy / 11.0) - 0.5;
    float fiber = sin(FRAGCOORD.y * 0.22 + paper_density(FRAGCOORD.xy / 31.0) * 2.0);
    float texture_value = (density + fiber * 0.08) * paper_strength;
    COLOR = vec4(mix(map.rgb, map.rgb * ink, season_strength) + texture_value, map.a);
}
