// An oil drum used as a brazier: rusted, scorched, with a ring of holes
// punched round its upper half that glow with the fire inside, the glow
// breathing with it. Procedural (the drum's cylinder UVs: u round, v up).
shader_type spatial;
render_mode cull_back;

uniform vec3 iron : source_color = vec3(0.16, 0.14, 0.12);
uniform vec3 rust : source_color = vec3(0.36, 0.17, 0.08);
uniform vec3 ember : source_color = vec3(1.0, 0.42, 0.1);
uniform float glow = 1.0;
uniform float phase = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	// rust in patches, scorched black toward the top
	float r = noise(uv * vec2(9.0, 4.0)) * 0.6 + noise(uv * vec2(23.0, 11.0)) * 0.4;
	float scorch = smoothstep(0.35, 0.95, uv.y) * 0.6;
	vec3 col = mix(iron, rust, smoothstep(0.45, 0.75, r)) * (1.0 - scorch);
	// the holes: three staggered rows round the upper half
	float gl = 0.0;
	for (int row = 0; row < 3; row++) {
		float vy = 0.5 + float(row) * 0.14;
		float ux = uv.x * 14.0 + (row == 1 ? 0.5 : 0.0);
		vec2 c = vec2(fract(ux) - 0.5, (uv.y - vy) * 14.0 * 0.5 / 0.5);
		float d = length(vec2(c.x, c.y * 0.9));
		gl += smoothstep(0.22, 0.14, d);
	}
	float breathe = 0.8 + 0.2 * sin(TIME * 6.1 + phase) * sin(TIME * 2.3 + phase * 1.7);
	ALBEDO = col;
	METALLIC = 0.55;
	ROUGHNESS = 0.75 + 0.2 * r;
	// a hot band under the lip, and the holes
	float band = smoothstep(0.8, 0.98, uv.y) * 0.35;
	EMISSION = ember * (gl * 2.2 + band) * glow * breathe;
}
