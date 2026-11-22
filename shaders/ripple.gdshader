shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;
// A ring spreading out on still water from a footstep, fading as it goes.
instance uniform float start = -100.0;

void fragment() {
	float age = TIME - start;
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float front = age * 1.4;
	float ring = smoothstep(0.06, 0.0, abs(r - front)) + 0.5 * smoothstep(0.05, 0.0, abs(r - front * 0.6));
	float fade = clamp(1.0 - age / 1.2, 0.0, 1.0) * step(r, 1.0);
	ALBEDO = vec3(0.35, 0.34, 0.33);
	ALPHA = ring * fade * 0.25;
}
