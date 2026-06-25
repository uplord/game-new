shader_type canvas_item;

render_mode blend_mix;

uniform bool selected = false;
uniform float edge_softness : hint_range(0.0, 0.2) = 0.08;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(vec2(uv.x * 2.8, uv.y * 4.3));

	float alpha = 1.0 - smoothstep(1.0 - edge_softness, 1.0, dist);

	if (selected) {
		COLOR = vec4(1.0, 0.733, 0.0, alpha * 0.5);
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, alpha * 0.15);
	}
}