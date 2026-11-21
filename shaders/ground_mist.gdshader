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
	DENSITY = density * h * in_trench * mix(0.35, 1.6, patches) * out_there * edge;
	ALBEDO = tint;
}
