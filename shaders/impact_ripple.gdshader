shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
// A ripple ring on standing water: a bright thin ring that widens (the mesh is
// scaled by the manager) and fades, with a dimmer second ring inside it.

uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 tint : source_color = vec3(0.85, 0.87, 0.82);

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float ring = smoothstep(0.78, 0.9, r) * (1.0 - smoothstep(0.9, 1.0, r));
	float ring2 = smoothstep(0.5, 0.58, r) * (1.0 - smoothstep(0.58, 0.68, r)) * 0.45;
	float a = (ring + ring2) * fade * fade * 0.55;
	ALBEDO = tint;
	ALPHA = a;
}
