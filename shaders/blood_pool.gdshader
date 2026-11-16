shader_type spatial;
// A pool of blood that creeps outward across the floor with an uneven edge.
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled, specular_schlick_ggx;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 thin_color : source_color = vec3(0.13, 0.008, 0.010);
uniform vec3 deep_color : source_color = vec3(0.035, 0.001, 0.003);
// Oil (the Klappersoldat): a faint rainbow film over the dark surface. 0 for blood.
uniform float sheen = 0.0;
instance uniform float grow = 0.0;   // 0..1, pool radius as a fraction of the quad
instance uniform float seed = 0.0;
instance uniform float fade = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float n = texture(noise_tex, p * 0.42 + vec2(seed, seed * 1.7)).r * 0.65
		+ texture(noise_tex, p * 1.5 + vec2(seed * 2.3, seed)).r * 0.35;
	float front = grow * (0.55 + 0.7 * n);      // how far the blood has reached here
	float d = front - r;
	if (d <= 0.0) {
		discard;
	}
	float edge = smoothstep(0.0, 0.008, d);
	float depth = smoothstep(0.0, 0.05 + grow * 0.22, d);
	ALBEDO = mix(thin_color, deep_color, depth);
	if (sheen > 0.0) {
		float film = n * 9.0 + r * 5.0 + dot(VIEW, NORMAL) * 4.0;
		vec3 rainbow = 0.5 + 0.5 * cos(film + vec3(0.0, 2.1, 4.2));
		// strongest in the thin film near the edge, barely there in the deep middle
		ALBEDO += rainbow * sheen * 0.012 * (1.0 - depth * 0.7);
	}
	ROUGHNESS = mix(0.2, 0.025, depth);
	SPECULAR = 0.5;
	METALLIC = 0.0;
	// Rounded lip at the edge, the way thick liquid stands on a floor.
	float lip = 1.0 - smoothstep(0.0, 0.03, d);
	vec2 dir = r > 0.0001 ? p / r : vec2(0.0);
	NORMAL = normalize(NORMAL + (TANGENT * dir.x + BINORMAL * dir.y) * lip * 0.3);
	ALPHA = edge * mix(0.9, 0.99, depth) * fade;
}
