shader_type spatial;
// A pool of blood (or oil) lying on the floor mesh BloodPool built for it.
// CUSTOM0: for each of up to four sources, how far out this point is as a
// fraction of that source's outline (1 = its edge). Each source's front is
// drawn up to its own outline, so the edge is a smooth curve worked out per
// pixel (no stair-steps along the sampling grid). UV2.y: how thick it can get
// here. COLOR.a: 1 on the strips down step faces. The pool spreads as the
// Blood manager raises `progress`; source i starts spreading at shifts[i].
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_schlick_ggx;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
// dark, close to the first pools' colours: fresh blood on a floor is nearly black-red
uniform vec3 thin_color : source_color = vec3(0.22, 0.013, 0.016);
uniform vec3 deep_color : source_color = vec3(0.085, 0.004, 0.007);
uniform vec3 dry_color : source_color = vec3(0.06, 0.016, 0.011);
uniform vec3 brown_color : source_color = vec3(0.13, 0.035, 0.022);   // oxidised patches
// Oil (the Klappersoldat): a faint rainbow film over the dark surface. 0 for blood.
uniform float sheen = 0.0;
uniform float edge_irregularity : hint_range(0.0, 2.0) = 1.0;
uniform bool wet_reflections = true;
uniform float droplets : hint_range(0.0, 2.0) = 1.0;
uniform float clotting : hint_range(0.0, 1.0) = 1.0;     // darker clumps and a skin of fine bumps

instance uniform float progress = 0.0;
instance uniform vec4 shifts = vec4(0.0, 1000.0, 1000.0, 1000.0);
instance uniform float fade = 1.0;
instance uniform float seed = 0.0;
instance uniform float age = 0.0;      // 0 fresh .. 1 dried

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 rels;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	rels = CUSTOM0;
}

float hgt(vec2 p) {
	// the skin of thick blood: a slow swell and fine crinkles
	return texture(noise_tex, p * 1.6 + vec2(seed * 0.9, seed * 1.3)).r;
}

void fragment() {
	float pot = UV2.y;
	bool riser = COLOR.a > 0.5;
	vec2 p = riser ? vec2(wpos.x + wpos.z, wpos.y * 1.6) : wpos.xz;
	float n1 = texture(noise_tex, p * 0.9 + vec2(seed, seed * 1.37)).r;
	float n2 = texture(noise_tex, p * 3.1 + vec2(seed * 2.1, seed)).r;
	float n3 = texture(noise_tex, p * 9.7 + vec2(seed * 0.7, seed * 3.1)).r;
	// how far inside its front this point is: the best over the sources, each
	// spreading up to its own outline and no further
	vec4 grown = min(vec4(progress) - shifts, vec4(1.0));
	vec4 ins = grown - rels;
	float e = max(max(ins.x, ins.y), max(ins.z, ins.w));
	float rel = min(min(rels.x, rels.y), min(rels.z, rels.w));
	// an organic, softly wandering front (in fractions of the outline)
	e += ((n1 - 0.5) * 0.16 + (n2 - 0.5) * 0.06) * edge_irregularity;
	if (riser) {
		// runs down the face: thin vertical lanes, not a sheet
		float along = wpos.x + wpos.z;
		float lane = texture(noise_tex, vec2(along * 4.0 + seed, wpos.y * 0.3)).r * 0.55
			+ texture(noise_tex, vec2(along * 13.0 + seed * 1.9, wpos.y * 0.6)).r * 0.45;
		e -= smoothstep(0.44, 0.56, lane) * 0.7 + (1.0 - lane) * 0.15;
	}
	float drop = 0.0;
	if (e < 0.0) {
		// a few separate droplets just past the front
		drop = step(-0.08, e) * smoothstep(0.79, 0.81, n3 + e * 2.4) * step(0.01, droplets) * step(0.5, 1.0 - float(riser));
		if (drop <= 0.0) {
			discard;
		}
	}
	// an anti-aliased edge: about a pixel and a half wide wherever it is
	float aa = max(fwidth(e) * 1.5, 0.003);
	float cover = max(smoothstep(0.0, aa, e), drop);
	// thickness: deeper toward the middle and the longer it has been pooling
	float thick = clamp(e * 3.2, 0.0, 1.0) * (0.35 + 0.65 * max(pot, 1.0 - rel)) * (0.85 + 0.3 * n1);
	thick = max(thick, drop * 0.3);
	vec3 col = mix(thin_color, deep_color, smoothstep(0.0, 0.55, thick));
	// mottling: patches of crimson (light through it) and near-black, a brownish
	// oxidised cast in places, and a fine grain
	float m1 = texture(noise_tex, p * 0.55 + vec2(seed * 1.9, seed * 0.3)).r;
	float m2 = texture(noise_tex, p * 5.3 + vec2(seed * 0.2, seed * 2.7)).r;
	float m3 = texture(noise_tex, p * 21.0 + vec2(seed * 3.1, seed * 1.1)).r;
	col = mix(col, thin_color * 0.85, smoothstep(0.6, 0.85, m1) * 0.25 * thick);
	col = mix(col, deep_color * 0.55, smoothstep(0.42, 0.18, m1) * 0.35 * thick);
	col = mix(col, brown_color, smoothstep(0.55, 0.8, m2) * 0.12);
	col *= 0.93 + 0.14 * m3;
	// clots: darker, duller clumps where it lies thick
	float clot = smoothstep(0.58, 0.78, texture(noise_tex, p * 1.7 + vec2(seed * 3.3, seed * 0.6)).r) * smoothstep(0.25, 0.7, thick) * clotting;
	col *= 1.0 - 0.35 * clot;
	// the meniscus: a narrow band at the edge where the surface curves down to the floor
	float lip = 1.0 - smoothstep(0.0, 0.07, e);
	col = mix(col, deep_color, lip * 0.3);
	// it dries from the thin edges in, going brown and dull
	float dry = age * (1.0 - 0.6 * smoothstep(0.2, 0.9, thick));
	col = mix(col, dry_color * (0.8 + 0.4 * n2), dry * 0.8);
	if (sheen > 0.0) {
		float film = n1 * 9.0 + n2 * 4.0 + dot(VIEW, NORMAL) * 4.0;
		vec3 rainbow = 0.5 + 0.5 * cos(film + vec3(0.0, 2.1, 4.2));
		col += rainbow * sheen * 0.012 * (1.0 - thick * 0.7);
	}
	ALBEDO = col;
	// roughness that varies across the pool, never one even gloss: thick fresh blood
	// 0.2-0.4 with broken wet patches (the small sharp highlights), duller clotted
	// islands, matte thin film and rough stretches along parts of the edge
	float r = mix(0.55, 0.24, smoothstep(0.0, 0.6, thick));
	float wetp = smoothstep(0.58, 0.72, texture(noise_tex, p * 1.25 + vec2(seed * 0.7, seed * 2.2)).r);
	r -= wetp * 0.14 * smoothstep(0.2, 0.6, thick);           // down to about 0.1: small sharp highlights
	r += clot * 0.3;
	r += smoothstep(0.5, 0.75, m2) * 0.12;                       // dull mottles
	r += lip * smoothstep(0.45, 0.7, n2) * 0.25;                 // rough, tacky stretches of the rim
	r += (m3 - 0.5) * 0.1;
	r = mix(r, 0.62, dry);
	if (!wet_reflections) {
		r = max(r, 0.55);
	}
	ROUGHNESS = clamp(r, 0.08, 0.9);
	SPECULAR = 0.25;                                             // F0 about 0.02, as water (blood n = 1.35)
	METALLIC = 0.0;
	// the surface: the lip rounds down to the floor at the edge (bend the normal
	// out along the front's slope), and thick blood has a faint crinkled skin
	vec3 dpx = dFdx(wpos);
	vec3 dpy = dFdy(wpos);
	vec3 r1 = cross(dpy, wnrm);
	vec3 r2 = cross(wnrm, dpx);
	float det = dot(dpx, r1);
	vec3 grad = (r1 * dFdx(e) + r2 * dFdy(e)) / (abs(det) > 1e-9 ? det : 1e-9);
	float gl = length(grad);
	vec3 nw = wnrm;
	if (!riser) {
		if (gl > 1e-5) {
			nw -= grad / gl * lip * 0.45;
		}
		float eps = 0.004;
		float h0 = hgt(p);
		vec2 g2 = vec2(hgt(p + vec2(eps, 0.0)) - h0, hgt(p + vec2(0.0, eps)) - h0) / eps;
		nw -= vec3(g2.x, 0.0, g2.y) * 0.0008 * thick * clotting;
		// a faint ripple in the wet patches: the bulb breaks into glints there
		float q0 = texture(noise_tex, p * 9.0 + vec2(seed * 1.3, seed)).r;
		vec2 gq = vec2(texture(noise_tex, (p + vec2(eps, 0.0)) * 9.0 + vec2(seed * 1.3, seed)).r - q0,
			texture(noise_tex, (p + vec2(0.0, eps)) * 9.0 + vec2(seed * 1.3, seed)).r - q0) / eps;
		nw -= vec3(gq.x, 0.0, gq.y) * 0.006 * wetp * thick;
	}
	nw = normalize(nw);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	// the thinnest smear at the edge lets the floor show a little; the rest is opaque
	ALPHA = cover * mix(0.78, 1.0, smoothstep(0.0, 0.25, thick)) * fade;
}
