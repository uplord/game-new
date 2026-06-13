shader_type canvas_item;

render_mode blend_mix;

uniform float opacity : hint_range(0.0, 1.0) = 0.1;
uniform float softness : hint_range(0.0, 0.5) = 0.25;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv * 2.0);

    float alpha = 1.0 - smoothstep(1.0 - softness, 1.0, dist);

    COLOR = vec4(0.0, 0.0, 0.0, alpha * opacity);
}