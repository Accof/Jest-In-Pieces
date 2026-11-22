shader_type fog;
// Ground mist for the trench floors: a low, thin, drifting layer hugging the
// ground, thicker out over No Man's Land (z below nml_z) and thinner down in
// the trenches, so the fire bays and the men in them stay readable while the
// far side is half lost. Rendered by the volumetric fog (Forward+ only).

uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float density = 0.06;          // at the ground, in the open, between the patches
uniform float height = 0.9;            // e-folding height above the ground (m)
uniform float ground_y = 0.0;          // the top of the ground, roughly
uniform float nml_z = 6.0;             // world z where No Man's Land begins (it lies toward -z)
uniform float nml_boost = 2.4;         // how much thicker it is out there
uniform float trench_keep = 0.35;      // how much of it settles in the trenches (at the floor)
uniform vec2 wind = vec2(0.32, 0.11);  // drift, m/s
uniform vec3 tint : source_color = vec3(0.63, 0.67, 0.72);
// The weather (TrenchFog): the whole mist thicker or thinner, and up to three
// fog banks rolling across: bank_a = middle (on the ground) and radius,
// bank_b = height over the ground, density now, a seed.
uniform float density_scale = 1.0;
uniform int bank_count = 0;
uniform vec4 bank_a[3];
uniform vec4 bank_b[3];
uniform vec3 bank_tint : source_color = vec3(0.85, 0.86, 0.87);

void fog() {
	vec3 p = WORLD_POSITION;
	float above = p.y - ground_y;
	// falls off with height above the ground; in the trench it thins toward the floor
	float h = exp(-max(above, 0.0) / height);
	float in_trench = mix(trench_keep, 1.0, smoothstep(-1.8, -0.1, above));
	// drifting patches, two scales moving at different speeds
	vec2 a = p.xz * 0.035 - wind * TIME * 0.035;
	vec2 b = p.xz * 0.11 - wind * TIME * 0.11 * 1.3 + vec2(0.37, 0.71);
	float n = texture(noise_tex, a).r * 0.65 + texture(noise_tex, b).g * 0.35;
	float patches = smoothstep(0.3, 0.75, n + (p.y - ground_y) * 0.05);
	float out_there = mix(1.0, nml_boost, smoothstep(nml_z, nml_z - 18.0, p.z));
	// fades out at the box's edges so it never ends in a wall
	vec3 e = min(UVW, 1.0 - UVW);
	float edge = smoothstep(0.0, 0.08, min(e.x, e.z)) * smoothstep(0.0, 0.15, e.y);
	float base = density * density_scale * h * in_trench * mix(0.35, 1.6, patches) * out_there;
	// the banks: a billowing cloud standing a few metres deep over the ground,
	// pouring into the trenches (no thinning down there, it fills them)
	float banks = 0.0;
	for (int i = 0; i < bank_count; i++) {
		vec4 a4 = bank_a[i];
		vec4 b4 = bank_b[i];
		vec2 rel = (p.xz - a4.xz) / a4.w;
		vec2 bw = p.xz * 0.06 + vec2(b4.z, b4.z * 0.7) + vec2(TIME * 0.02, -TIME * 0.015);
		float billow = texture(noise_tex, bw).r * 0.6 + texture(noise_tex, p.xy * 0.09 + vec2(b4.z * 1.3, TIME * 0.01)).g * 0.4;
		float core = 1.0 - smoothstep(0.3, 1.0, length(rel) + (billow - 0.5) * 0.5);
		float top = max(ground_y, 0.0) + b4.x * (0.75 + 0.5 * billow);
		float v = 1.0 - smoothstep(top - b4.x * 0.55, top, p.y);
		banks += b4.y * core * v * mix(0.55, 1.3, billow);
	}
	banks *= 0.3;
	DENSITY = (base + banks) * edge;
	ALBEDO = mix(tint, bank_tint, clamp(banks / max(base + banks, 0.0001), 0.0, 1.0));
}
