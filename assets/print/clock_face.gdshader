shader_type canvas_item;
render_mode unshaded;

uniform float day_phase : hint_range(0.0, 1.0) = 0.0;
uniform float year_phase : hint_range(0.0, 1.0) = 0.0;
uniform float daylight_fraction : hint_range(0.0, 1.0) = 0.5;
uniform vec4 paper_color : source_color = vec4(0.941, 0.925, 0.875, 1.0);
uniform vec4 ink_color : source_color = vec4(0.157, 0.192, 0.180, 1.0);
uniform vec4 day_color : source_color = vec4(0.741, 0.616, 0.345, 1.0);
uniform vec4 night_color : source_color = vec4(0.365, 0.447, 0.475, 1.0);
uniform vec4 spring_color : source_color = vec4(0.518, 0.600, 0.451, 1.0);
uniform vec4 summer_color : source_color = vec4(0.784, 0.667, 0.404, 1.0);
uniform vec4 autumn_color : source_color = vec4(0.682, 0.431, 0.329, 1.0);
uniform vec4 winter_color : source_color = vec4(0.514, 0.635, 0.655, 1.0);

float disc(float radius, float edge, float distance) {
    return 1.0 - smoothstep(radius - edge, radius + edge, distance);
}

void fragment() {
    vec2 point = UV - vec2(0.5);
    float radius = length(point);
    float angle = atan(point.x, -point.y);
    float edge = fwidth(radius);
    float stamp = disc(0.495, edge, radius);
    float fixed_angle = atan(sin(angle - PI), cos(angle - PI));
    float notch = smoothstep(0.51, 0.53, abs(fixed_angle));
    float day_ring = disc(0.475, edge, radius) - disc(0.451, edge, radius);
    float season_ring = disc(0.432, edge, radius) - disc(0.331, edge, radius);
    float local_day = fract(day_phase - (angle - PI) / TAU);
    float daylight = 1.0 - smoothstep(daylight_fraction * 0.5 - 0.012,
        daylight_fraction * 0.5 + 0.012, abs(local_day - 0.5));
    vec3 color = paper_color.rgb;
    color = mix(color, mix(night_color.rgb, day_color.rgb, daylight), day_ring * notch);
    float season = fract(year_phase - (angle - PI) / TAU);
    vec3 season_ink = season < 0.25 ? spring_color.rgb :
        (season < 0.5 ? summer_color.rgb : (season < 0.75 ? autumn_color.rgb : winter_color.rgb));
    color = mix(color, season_ink, season_ring * notch);
    float outline = disc(0.489, edge, radius) - disc(0.483, edge, radius);
    outline += disc(0.445, edge, radius) - disc(0.440, edge, radius);
    outline += disc(0.328, edge, radius) - disc(0.322, edge, radius);
    float ticks = 1.0 - smoothstep(0.015, 0.08, abs(sin(angle * 12.0)));
    float tick_band = smoothstep(0.454, 0.459, radius) * (1.0 - smoothstep(0.470, 0.475, radius));
    color = mix(color, ink_color.rgb, clamp(outline * notch + ticks * tick_band * notch * 0.7, 0.0, 1.0));
    float fiber = sin(FRAGCOORD.y * 0.41 + sin(FRAGCOORD.x * 0.061)) * 0.0015;
    COLOR = vec4(color + fiber, stamp * paper_color.a);
}
