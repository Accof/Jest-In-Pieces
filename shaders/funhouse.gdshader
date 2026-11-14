shader_type spatial;
// One material for the whole maze: checkerboard on anything flat, slanted
// carnival stripes on anything upright, all of it grimy.
uniform vec3 stripe_a : source_color = vec3(0.55, 0.08, 0.08);
uniform vec3 stripe_b : source_color = vec3(0.78, 0.72, 0.60);
uniform vec3 floor_a : source_color = vec3(0.07, 0.07, 0.08);
uniform vec3 floor_b : source_color = vec3(0.62, 0.58, 0.50);
uniform float stripe_width = 0.6;
uniform float checker_size = 0.75;
uniform float grime = 0.55;

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col;
	vec2 gp;
	if (abs(wnrm.y) > 0.5) {
		vec2 c = floor(wpos.xz / checker_size + 0.001);
		col = mod(c.x + c.y, 2.0) < 0.5 ? floor_a : floor_b;
		gp = wpos.xz;
	} else {
		float u = abs(wnrm.x) > 0.5 ? wpos.z : wpos.x;
		float s = fract((u + wpos.y * 0.35) / stripe_width);
		col = s < 0.5 ? stripe_a : stripe_b;
		gp = vec2(u, wpos.y);
		col *= mix(0.55, 1.0, smoothstep(0.0, 1.2, fract(wpos.y / 1.2) * 1.2 + 0.25));   // scuffed lower walls
	}
	float g = noise(gp * 1.7) * 0.6 + noise(gp * 6.0) * 0.4;
	col *= mix(1.0, 0.35 + 0.65 * g, grime);
	ALBEDO = col;
	ROUGHNESS = 0.78 + 0.15 * g;
	SPECULAR = 0.35;
}
